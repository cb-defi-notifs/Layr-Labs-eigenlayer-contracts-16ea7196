// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../permissions/Pausable.sol";
import "./InvestmentManagerStorage.sol";
import "../interfaces/IServiceManager.sol";
// import "forge-std/Test.sol";

/**
 * @title The primary entry- and exit-point for funds into and out of EigenLayr.
 * @author Layr Labs, Inc.
 * @notice This contract is for managing investments in different strategies. The main
 * functionalities are:
 * - adding and removing investment strategies that any delegator can invest into
 * - enabling deposit of assets into specified investment strategy(s)
 * - enabling removal of assets from specified investment strategy(s)
 * - recording deposit of ETH into settlement layer
 * - recording deposit of Eigen for securing EigenLayr
 * - slashing of assets for permissioned strategies
 */
contract InvestmentManager is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    InvestmentManagerStorage,
    Pausable
{
    using SafeERC20 for IERC20;

    /**
     * @notice Value to which `initTimestamp` and `unlockTimestamp` to is set to indicate a withdrawal is queued/initialized,
     * but has not yet had its waiting period triggered
     */
    uint32 internal constant QUEUED_WITHDRAWAL_INITIALIZED_VALUE = type(uint32).max;

    /// @notice Emitted when a new withdrawal is queued by `depositor`
    event WithdrawalQueued(address indexed depositor, address indexed withdrawer, bytes32 withdrawalRoot);
    /// @notice Emitted when a queued withdrawal is completed
    event WithdrawalCompleted(address indexed depositor, address indexed withdrawer, bytes32 withdrawalRoot);

    modifier onlyNotDelegated(address user) {
        require(delegation.isNotDelegated(user), "InvestmentManager.onlyNotDelegated: user is actively delegated");
        _;
    }

    modifier onlyNotFrozen(address staker) {
        require(
            !slasher.isFrozen(staker),
            "InvestmentManager.onlyNotFrozen: staker has been frozen and may be subject to slashing"
        );
        _;
    }

    modifier onlyFrozen(address staker) {
        require(slasher.isFrozen(staker), "InvestmentManager.onlyFrozen: staker has not been frozen");
        _;
    }

    constructor(IEigenLayrDelegation _delegation) InvestmentManagerStorage(_delegation) {
        _disableInitializers();
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Initializes the investment manager contract.
     * @param _slasher The primary slashing contract of EigenLayr.
     * @param _pauserRegistry Used for access control of pausing.
     * @param initialOwner Ownership of this contract is transferred to this address.
     */
    function initialize(ISlasher _slasher, IPauserRegistry _pauserRegistry, address initialOwner)
        external
        initializer
    {
        _transferOwnership(initialOwner);
        slasher = _slasher;
        _initializePauser(_pauserRegistry);
    }
    /**
     * @notice Deposits `amount` of `token` into the specified `strategy`, with the resultant shares credited to `depositor`
     * @param strategy is the specified strategy where investment is to be made,
     * @param token is the denomination in which the investment is to be made,
     * @param amount is the amount of token to be invested in the strategy by the depositor
     */

    function depositIntoStrategy(IInvestmentStrategy strategy, IERC20 token, uint256 amount)
        external
        onlyNotFrozen(msg.sender)
        nonReentrant
        returns (uint256 shares)
    {
        shares = _depositIntoStrategy(msg.sender, strategy, token, amount);
    }

    /**
     * @notice used for investing an asset into the specified strategy on behalf of a staker who must sign off on the action
     */
    /**
     * @param strategy is the specified strategy where investment is to be made,
     * @param token is the denomination in which the investment is to be made,
     * @param amount is the amount of token to be invested in the strategy by the depositor
     * @param staker the staker that the assets will be deposited on behalf of
     * @param expiry the timestamp at which the signature expires
     * @param r and @param vs are the elements of the ECDSA signature
     */
    function depositIntoStrategyOnBehalfOf(
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 amount,
        address staker,
        uint256 expiry,
        bytes32 r,
        bytes32 vs
    )
        external
        nonReentrant
        returns (uint256 shares)
    {
        // make not frozen check here instead of modifier
        require(
            !slasher.isFrozen(staker),
            "InvestmentManager.depositIntoStrategyOnBehalfOf: staker has been frozen and may be subject to slashing"
        );

        require(
            expiry == 0 || expiry >= block.timestamp,
            "InvestmentManager.depositIntoStrategyOnBehalfOf: delegation signature expired"
        );
        // calculate struct hash, then increment `staker`'s nonce
        bytes32 structHash = keccak256(abi.encode(DEPOSIT_TYPEHASH, strategy, token, amount, nonces[staker]++, expiry));
        bytes32 digestHash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        // check validity of signature
        address recoveredAddress = ECDSA.recover(digestHash, r, vs);
        require(recoveredAddress == staker, "InvestmentManager.depositIntoStrategyOnBehalfOf: sig not from staker");

        shares = _depositIntoStrategy(staker, strategy, token, amount);
    }

    /**
     * @notice Called by a staker to undelegate entirely from EigenLayer. The staker must first withdraw all of their existing deposits
     * (through use of the `queueWithdrawal` function), or else otherwise have never deposited in EigenLayer prior to delegating.
     */
    function undelegate() external {
        require(investorStrats[msg.sender].length == 0, "InvestmentManager.undelegate: staker has active deposits");
        _undelegateIfPossible(msg.sender);
    }

    /**
     * @notice Used to withdraw the given token and shareAmount from the given strategy.
     * @dev Only those stakers who have undelegated entirely from EigenLayer (or never delegated in the first place)
     * can call this function.
     */
    function withdrawFromStrategy(
        uint256 strategyIndex,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 shareAmount
    )
        external
        whenNotPaused
        onlyNotFrozen(msg.sender)
        onlyNotDelegated(msg.sender)
        nonReentrant
    {
        _withdrawFromStrategy(msg.sender, strategyIndex, strategy, token, shareAmount);
        //decrease corresponding operator's shares, if applicable
        delegation.decreaseDelegatedShares(msg.sender, strategy, shareAmount);
    }

    /**
     * @notice Called by a staker to queue a withdraw in the given token and shareAmount from each of the respective given strategies.
     */
    /**
     * @dev Stakers will complete their withdrawal by calling the 'completeQueuedWithdrawal' function.
     * User shares are decreased in this function, but the total number of shares in each strategy remains the same.
     * The total number of shares is decremented in the 'completeQueuedWithdrawal' function instead, which is where
     * the funds are actually sent to the user through use of the strategies' 'withdrawal' function. This ensures
     * that the value per share reported by each strategy will remain consistent, and that the shares will continue
     * to accrue gains during the enforced WITHDRAWAL_WAITING_PERIOD.
     */
    function queueWithdrawal(
        uint256[] calldata strategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shares,
        WithdrawerAndNonce calldata withdrawerAndNonce
    )
        external
        whenNotPaused
        onlyNotFrozen(msg.sender)
        nonReentrant
        returns (bytes32)
    {
        require(
            withdrawerAndNonce.nonce == numWithdrawalsQueued[msg.sender],
            "InvestmentManager.queueWithdrawal: provided nonce incorrect"
        );
        // increment the numWithdrawalsQueued of the sender
        unchecked {
            ++numWithdrawalsQueued[msg.sender];
        }

        uint256 strategyIndexIndex;

        // modify delegated shares accordingly, if applicable
        delegation.decreaseDelegatedShares(msg.sender, strategies, shares);

        uint256 strategiesLength = strategies.length;
        for (uint256 i = 0; i < strategiesLength;) {
            // the internal function will return 'true' in the event the strategy was
            // removed from the depositor's array of strategies -- i.e. investorStrats[depositor]
            if (_removeShares(msg.sender, strategyIndexes[strategyIndexIndex], strategies[i], shares[i])) {
                unchecked {
                    ++strategyIndexIndex;
                }
            }

            //increment the loop
            unchecked {
                ++i;
            }
        }

        bytes32 withdrawalRoot = calculateWithdrawalRoot(strategies, tokens, shares, withdrawerAndNonce);

        //update storage in mapping of queued withdrawals
        queuedWithdrawals[msg.sender][withdrawalRoot] = WithdrawalStorage({
            initTimestamp: QUEUED_WITHDRAWAL_INITIALIZED_VALUE,
            withdrawer: withdrawerAndNonce.withdrawer,
            unlockTimestamp: QUEUED_WITHDRAWAL_INITIALIZED_VALUE
        });

        emit WithdrawalQueued(msg.sender, withdrawerAndNonce.withdrawer, withdrawalRoot);

        return withdrawalRoot;
    }
    /*
    * 
    * The withdrawal flow is:
    * - Depositer starts a queued withdrawal, setting the receiver of the withdrawn funds as withdrawer
    * - Withdrawer then waits for the queued withdrawal tx to be included in the chain, and then sets the stakeInactiveAfter. This cannot
    *   be set when starting the queued withdrawal, as it is there may be transactions the increase the tasks upon which the stake is active 
    *   that get mined before the withdrawal.
    * - The withdrawer completes the queued withdrawal after the stake is inactive or a withdrawal fraud proof period has passed,
    *   whichever is longer. They specify whether they would like the withdrawal in shares or in tokens.
    */

    function startQueuedWithdrawalWaitingPeriod(address depositor, bytes32 withdrawalRoot, uint32 stakeInactiveAfter)
        external
    {
        require(
            queuedWithdrawals[depositor][withdrawalRoot].initTimestamp == type(uint32).max,
            "Withdrawal stake inactive claim has already been made"
        );
        require(
            queuedWithdrawals[depositor][withdrawalRoot].withdrawer == msg.sender,
            "InvestmentManager.setStakeInactiveAfterClaim: Sender is not the withdrawer"
        );
        //they can only unlock after a withdrawal waiting period or after they are claiming their stake is inactive
        queuedWithdrawals[depositor][withdrawalRoot] = WithdrawalStorage({
            initTimestamp: uint32(block.timestamp),
            withdrawer: msg.sender,
            unlockTimestamp: max((uint32(block.timestamp) + WITHDRAWAL_WAITING_PERIOD), stakeInactiveAfter)
        });
    }

    function max(uint32 x, uint32 y) internal pure returns (uint32) {
        return x > y ? x : y;
    }

    /**
     * @notice Used to complete a queued withdraw in the given token and shareAmount from each of the respective given strategies,
     * that was initiated by 'depositor'. The 'withdrawer' address is looked up in storage.
     */
    function completeQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shares,
        address depositor,
        WithdrawerAndNonce calldata withdrawerAndNonce,
        bool receiveAsTokens
    )
        external
        whenNotPaused
        onlyNotFrozen(depositor)
        nonReentrant
    {
        // find the withdrawalRoot
        bytes32 withdrawalRoot = calculateWithdrawalRoot(strategies, tokens, shares, withdrawerAndNonce);
        // copy storage to memory
        WithdrawalStorage memory withdrawalStorageCopy = queuedWithdrawals[depositor][withdrawalRoot];

        // verify that the queued withdrawal actually exists
        require(
            withdrawalStorageCopy.initTimestamp > 0,
            "InvestmentManager.completeQueuedWithdrawal: withdrawal does not exist"
        );

        require(
            uint32(block.timestamp) >= withdrawalStorageCopy.unlockTimestamp || delegation.isNotDelegated(depositor),
            "InvestmentManager.completeQueuedWithdrawal: withdrawal waiting period has not yet passed and depositor is still delegated"
        );

        // TODO: add testing coverage for this
        require(
            msg.sender == withdrawerAndNonce.withdrawer,
            "InvestmentManager.completeQueuedWithdrawal: only specified withdrawer can complete a queued withdrawal"
        );

        // reset the storage slot in mapping of queued withdrawals
        delete queuedWithdrawals[depositor][withdrawalRoot];

        // undelegate the `depositor`, if they have no existing shares
        _undelegateIfPossible(depositor);

        // store length for gas savings
        uint256 strategiesLength = strategies.length;
        // if the withdrawer has flagged to receive the funds as tokens, withdraw from strategies
        if (receiveAsTokens) {
            // actually withdraw the funds
            for (uint256 i = 0; i < strategiesLength;) {
                // tell the strategy to send the appropriate amount of funds to the depositor
                strategies[i].withdraw(withdrawalStorageCopy.withdrawer, tokens[i], shares[i]);
                unchecked {
                    ++i;
                }
            }
        } else {
            // else increase their shares
            for (uint256 i = 0; i < strategiesLength;) {
                _addShares(withdrawalStorageCopy.withdrawer, strategies[i], shares[i]);
                unchecked {
                    ++i;
                }
            }
        }

        emit WithdrawalCompleted(depositor, withdrawalStorageCopy.withdrawer, withdrawalRoot);
    }

    /**
     * @notice Used prove that the funds to be withdrawn in a queued withdrawal are still at stake in an active query.
     * The result is resetting the WITHDRAWAL_WAITING_PERIOD for the queued withdrawal.
     * @dev The fraudproof requires providing a repository contract and queryHash, corresponding to a query that was
     * created at or before the time when the queued withdrawal was initiated, and expires prior to the time at
     * which the withdrawal can currently be completed. A successful fraudproof sets the queued withdrawal's
     * 'unlockTimestamp' to the current UTC time plus the WITHDRAWAL_WAITING_PERIOD, pushing back the unlock time for the funds to be withdrawn.
     */
    function challengeQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shares,
        address depositor,
        WithdrawerAndNonce calldata withdrawerAndNonce,
        bytes calldata data,
        IServiceManager slashingContract
    )
        external
    {
        // find the withdrawalRoot
        bytes32 withdrawalRoot = calculateWithdrawalRoot(strategies, tokens, shares, withdrawerAndNonce);
        // copy storage to memory
        WithdrawalStorage memory withdrawalStorageCopy = queuedWithdrawals[depositor][withdrawalRoot];

        //verify the withdrawer has supplied the unbonding time
        require(
            withdrawalStorageCopy.initTimestamp != type(uint32).max,
            "InvestmentManager.fraudproofQueuedWithdrawal: withdrawal was been initialized, but waiting period hasn't begun"
        );

        // verify that the queued withdrawal actually exists
        require(
            withdrawalStorageCopy.initTimestamp > 0,
            "InvestmentManager.fraudproofQueuedWithdrawal: withdrawal does not exist"
        );

        // check that it is not too late to provide a fraudproof
        require(
            uint32(block.timestamp) < withdrawalStorageCopy.unlockTimestamp,
            "InvestmentManager.fraudproofQueuedWithdrawal: withdrawal waiting period has already passed"
        );

        address operator = delegation.delegation(depositor);

        require(
            slasher.canSlash(operator, address(slashingContract)),
            "InvestmentManager.fraudproofQueuedWithdrawal: Contract does not have rights to slash operator"
        );

        {
            // ongoing task is still active at time when staker was finalizing undelegation
            // and, therefore, hasn't served its obligation.
            slashingContract.stakeWithdrawalVerification(
                data, withdrawalStorageCopy.initTimestamp, withdrawalStorageCopy.unlockTimestamp
            );
        }

        // set the withdrawer equal to address(0), allowing the slasher custody of the funds
        queuedWithdrawals[depositor][withdrawalRoot].withdrawer = address(0);
    }

    /// @notice Slashes the shares of 'frozen' operator (or a staker delegated to one)
    function slashShares(
        address slashedAddress,
        address recipient,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata strategyIndexes,
        uint256[] calldata shareAmounts
    )
        external
        whenNotPaused
        onlyOwner
        onlyFrozen(slashedAddress)
        nonReentrant
    {
        uint256 strategyIndexIndex;
        uint256 strategiesLength = strategies.length;
        for (uint256 i = 0; i < strategiesLength;) {
            // the internal function will return 'true' in the event the strategy was
            // removed from the slashedAddress's array of strategies -- i.e. investorStrats[slashedAddress]
            if (_removeShares(slashedAddress, strategyIndexes[strategyIndexIndex], strategies[i], shareAmounts[i])) {
                unchecked {
                    ++strategyIndexIndex;
                }
            }

            // withdraw the shares and send funds to the recipient
            strategies[i].withdraw(recipient, tokens[i], shareAmounts[i]);

            // increment the loop
            unchecked {
                ++i;
            }
        }

        // modify delegated shares accordingly, if applicable
        delegation.decreaseDelegatedShares(slashedAddress, strategies, shareAmounts);
    }

    /// @notice Slashes an existing queued withdrawal that was created by a 'frozen' operator (or a staker delegated to one)
    function slashQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shares,
        address depositor,
        address recipient,
        WithdrawerAndNonce calldata withdrawerAndNonce
    )
        external
        whenNotPaused
        onlyOwner
        nonReentrant
    {
        // find the withdrawalRoot
        bytes32 withdrawalRoot = calculateWithdrawalRoot(strategies, tokens, shares, withdrawerAndNonce);

        // verify that the queued withdrawal actually exists
        require(
            queuedWithdrawals[depositor][withdrawalRoot].initTimestamp > 0,
            "InvestmentManager.slashQueuedWithdrawal: withdrawal does not exist"
        );

        // verify that the queued withdrawal has been successfully challenged
        require(
            queuedWithdrawals[depositor][withdrawalRoot].withdrawer == address(0) || slasher.isFrozen(depositor),
            "InvestmentManager.slashQueuedWithdrawal: withdrawal has not been successfully challenged or depositor is not frozen"
        );

        // reset the storage slot in mapping of queued withdrawals
        delete queuedWithdrawals[depositor][withdrawalRoot];

        uint256 strategiesLength = strategies.length;
        for (uint256 i = 0; i < strategiesLength;) {
            // tell the strategy to send the appropriate amount of funds to the recipient
            strategies[i].withdraw(recipient, tokens[i], shares[i]);
            unchecked {
                ++i;
            }
        }
    }

    // INTERNAL FUNCTIONS

    /// @notice This function adds shares for a given strategy to a depositor and runs through the necessary update logic
    function _addShares(address depositor, IInvestmentStrategy strategy, uint256 shares) internal {
        // sanity check on `shares` input
        require(shares != 0, "InvestmentManager._addShares: shares should not be zero!");

        // if they dont have existing shares of this strategy, add it to their strats
        if (investorStratShares[depositor][strategy] == 0) {
            require(
                investorStrats[depositor].length <= MAX_INVESTOR_STRATS_LENGTH,
                "InvestmentManager._addShares: deposit would exceed MAX_INVESTOR_STRATS_LENGTH"
            );
            investorStrats[depositor].push(strategy);
        }

        // add the returned shares to their existing shares for this strategy
        investorStratShares[depositor][strategy] += shares;

        // if applicable, increase delegated shares accordingly
        delegation.increaseDelegatedShares(depositor, strategy, shares);
    }

    function _depositIntoStrategy(address depositor, IInvestmentStrategy strategy, IERC20 token, uint256 amount)
        internal
        returns (uint256 shares)
    {
        // transfer tokens from the sender to the strategy
        token.safeTransferFrom(msg.sender, address(strategy), amount);

        // deposit the assets into the specified strategy and get the equivalent amount of shares in that strategy
        shares = strategy.deposit(token, amount);

        // add the returned shares to the depositor's existing shares for this strategy
        _addShares(depositor, strategy, shares);

        return shares;
    }

    /**
     * @notice Withdraws `shareAmount` shares that `depositor` holds in `strategy`, to their address
     * @dev If the amount of shares represents all of the depositor`s shares in said strategy,
     * then the strategy is removed from investorStrats[depositor] and `true` is returned. Otherwise `false` is returned.
     */
    function _withdrawFromStrategy(
        address depositor,
        uint256 strategyIndex,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 shareAmount
    )
        internal
        returns (bool strategyRemovedFromArray)
    {
        strategyRemovedFromArray = _removeShares(depositor, strategyIndex, strategy, shareAmount);
        // tell the strategy to send the appropriate amount of funds to the depositor
        strategy.withdraw(depositor, token, shareAmount);
    }

    /**
     * @notice Decreases the shares that `depositor` holds in `strategy` by `shareAmount`.
     * @dev If the amount of shares represents all of the depositor`s shares in said strategy,
     * then the strategy is removed from investorStrats[depositor] and `true` is returned. Otherwise `false` is returned.
     */
    function _removeShares(address depositor, uint256 strategyIndex, IInvestmentStrategy strategy, uint256 shareAmount)
        internal
        returns (bool)
    {
        // sanity check on `shareAmount` input
        require(shareAmount != 0, "InvestmentManager._removeShares: shareAmount should not be zero!");

        //check that the user has sufficient shares
        uint256 userShares = investorStratShares[depositor][strategy];

        require(shareAmount <= userShares, "InvestmentManager._removeShares: shareAmount too high");
        //unchecked arithmetic since we just checked this above
        unchecked {
            userShares = userShares - shareAmount;
        }

        // subtract the shares from the depositor's existing shares for this strategy
        investorStratShares[depositor][strategy] = userShares;
        // if no existing shares, remove is from this investors strats

        if (userShares == 0) {
            // if the strategy matches with the strategy index provided
            if (investorStrats[depositor][strategyIndex] == strategy) {
                // replace the strategy with the last strategy in the list
                investorStrats[depositor][strategyIndex] =
                    investorStrats[depositor][investorStrats[depositor].length - 1];
            } else {
                //loop through all of the strategies, find the right one, then replace
                uint256 stratsLength = investorStrats[depositor].length;

                for (uint256 j = 0; j < stratsLength;) {
                    if (investorStrats[depositor][j] == strategy) {
                        //replace the strategy with the last strategy in the list
                        investorStrats[depositor][j] = investorStrats[depositor][investorStrats[depositor].length - 1];
                        break;
                    }
                    unchecked {
                        ++j;
                    }
                }
            }

            // pop off the last entry in the list of strategies
            investorStrats[depositor].pop();

            // return true in the event that the strategy was removed from investorStrats[depositor]
            return true;
        }
        // return false in the event that the strategy was *not* removed from investorStrats[depositor]
        return false;
    }


    /**
     * @notice If the `depositor` has no existing shares and they are delegated, undelegate them.
     * This allows people a "hard reset" in their relationship with EigenLayer after withdrawing all of their stake.
     */
    function _undelegateIfPossible(address depositor) internal {
        if (investorStrats[depositor].length == 0 && delegation.isDelegated(depositor)) {
            delegation.undelegate(depositor);
        }
    }

    // VIEW FUNCTIONS

    /**
     * @notice Used to check if a queued withdrawal can be completed
     */
    function canCompleteQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        address depositor,
        WithdrawerAndNonce calldata withdrawerAndNonce
    )
        external
        returns (bool)
    {
        // find the withdrawalRoot
        bytes32 withdrawalRoot = calculateWithdrawalRoot(strategies, tokens, shareAmounts, withdrawerAndNonce);

        // verify that the queued withdrawal actually exists
        require(
            queuedWithdrawals[depositor][withdrawalRoot].initTimestamp > 0,
            "InvestmentManager.canCompleteQueuedWithdrawal: withdrawal does not exist"
        );

        return (
            uint32(block.timestamp) >= queuedWithdrawals[depositor][withdrawalRoot].unlockTimestamp
                || delegation.isNotDelegated(depositor)
        );
    }

    /**
     * @notice Get all details on the depositor's investments and corresponding shares
     * @return (depositor's strategies, shares in these strategies)
     */
    function getDeposits(address depositor) external view returns (IInvestmentStrategy[] memory, uint256[] memory) {
        uint256 strategiesLength = investorStrats[depositor].length;
        uint256[] memory shares = new uint256[](strategiesLength);

        for (uint256 i = 0; i < strategiesLength;) {
            shares[i] = investorStratShares[depositor][investorStrats[depositor][i]];
            unchecked {
                ++i;
            }
        }
        return (investorStrats[depositor], shares);
    }

    function investorStratsLength(address investor) external view returns (uint256) {
        return investorStrats[investor].length;
    }

    function calculateWithdrawalRoot(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        WithdrawerAndNonce calldata withdrawerAndNonce
    )
        public
        pure
        returns (bytes32)
    {
        return (keccak256(abi.encode(strategies, tokens, shareAmounts, withdrawerAndNonce)));
    }
}
