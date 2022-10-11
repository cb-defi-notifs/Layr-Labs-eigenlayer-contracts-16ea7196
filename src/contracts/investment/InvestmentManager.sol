// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

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

    /**
     * @notice Emitted when a new withdrawal is queued by `depositor`.
     * @param depositor Is the staker who is withdrawing funds from EigenLayer.
     * @param withdrawer Is the party specified by `staker` who will be able to complete the queued withdrawal and receive the withdrawn funds.
     * @param delegatedAddress Is the party who the `staker` was delegated to at the time of creating the queued withdrawal
     * @param withdrawalRoot Is a hash of the input data for the withdrawal.
     */
    event WithdrawalQueued(
        address indexed depositor, address indexed withdrawer, address indexed delegatedAddress, bytes32 withdrawalRoot
    );
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
     * @notice used for investing an asset into the specified strategy on behalf of a staker, who must sign off on the action
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
        onlyNotFrozen(staker)
        nonReentrant
        returns (uint256 shares)
    {
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
        _undelegate(msg.sender);
    }

    /**
     * @notice Called by a staker to queue a withdraw in the given token and shareAmount from each of the respective given strategies.
     * @dev Stakers will complete their withdrawal by calling the 'completeQueuedWithdrawal' function.
     * User shares are decreased in this function, but the total number of shares in each strategy remains the same.
     * The total number of shares is decremented in the 'completeQueuedWithdrawal' function instead, which is where
     * the funds are actually sent to the user through use of the strategies' 'withdrawal' function. This ensures
     * that the value per share reported by each strategy will remain consistent, and that the shares will continue
     * to accrue gains during the enforced WITHDRAWAL_WAITING_PERIOD.
     * @param strategyIndexes is a list of the indices in `investorStrats[msg.sender]` that correspond to the strategies
     * for which `msg.sender` is withdrawing 100% of their shares
     * @dev strategies are removed from `investorStrats` by swapping the last entry with the entry to be removed, then
     * popping off the last entry in `investorStrats`. The simplest way to calculate the correct `strategyIndexes` to input
     * is to order the strategies *for which `msg.sender` is withdrawing 100% of their shares* from highest index in
     * `investorStrats` to lowest index
     */
    function queueWithdrawal(
        uint256[] calldata strategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shares,
        WithdrawerAndNonce calldata withdrawerAndNonce,
        bool undelegateIfPossible
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

        for (uint256 i = 0; i < strategies.length;) {
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

        // fetch the address that the `msg.sender` is delegated to
        address delegatedAddress = delegation.delegatedTo(msg.sender);

        // copy arguments into struct and pull delegation info
        QueuedWithdrawal memory queuedWithdrawal = QueuedWithdrawal({
            strategies: strategies,
            tokens: tokens,
            shares: shares,
            depositor: msg.sender,
            withdrawerAndNonce: withdrawerAndNonce,
            delegatedAddress: delegatedAddress
        });

        // calculate the withdrawal root
        bytes32 withdrawalRoot = calculateWithdrawalRoot(queuedWithdrawal);

        //update storage in mapping of queued withdrawals
        queuedWithdrawals[withdrawalRoot] = WithdrawalStorage({
            /**
             * @dev We add `REASONABLE_STAKES_UPDATE_PERIOD` to the current time here to account for the fact that it may take some time for
             * the operator's stake to be updated on all the middlewares. New tasks created between now at this 'initTimestamp' may still
             * subject the `msg.sender` to slashing!
             */
            initTimestamp: uint32(block.timestamp + REASONABLE_STAKES_UPDATE_PERIOD),
            withdrawer: withdrawerAndNonce.withdrawer,
            unlockTimestamp: QUEUED_WITHDRAWAL_INITIALIZED_VALUE
        });

        // If the `msg.sender` has withdrawn all of their funds from EigenLayer in this transaction, then they can choose to also undelegate
        /**
         * Checking that `investorStrats[msg.sender].length == 0` is not strictly necessary here, but prevents reverting very late in logic,
         * in the case that 'undelegate' is set to true but the `msg.sender` still has active deposits in EigenLayer.
         */
        if (undelegateIfPossible && investorStrats[msg.sender].length == 0) {
            _undelegate(msg.sender);
        }

        emit WithdrawalQueued(msg.sender, withdrawerAndNonce.withdrawer, delegatedAddress, withdrawalRoot);

        return withdrawalRoot;
    }

    /*
    * 
    * @notice The withdrawal flow is:
    * - Depositor starts a queued withdrawal, setting the receiver of the withdrawn funds as withdrawer
    * - Withdrawer then waits for the queued withdrawal tx to be included in the chain, and then sets the stakeInactiveAfter. This cannot
    *   be set when starting the queued withdrawal, as it is there may be transactions the increase the tasks upon which the stake is active 
    *   that get mined before the withdrawal.
    * - The withdrawer completes the queued withdrawal after the stake is inactive or a withdrawal fraud proof period has passed,
    *   whichever is longer. They specify whether they would like the withdrawal in shares or in tokens.
    */
    function startQueuedWithdrawalWaitingPeriod(bytes32 withdrawalRoot, uint32 stakeInactiveAfter) external {
        require(
            queuedWithdrawals[withdrawalRoot].unlockTimestamp == QUEUED_WITHDRAWAL_INITIALIZED_VALUE,
            "InvestmentManager.startQueuedWithdrawalWaitingPeriod: Withdrawal stake inactive claim has already been made"
        );
        require(
            queuedWithdrawals[withdrawalRoot].withdrawer == msg.sender,
            "InvestmentManager.startQueuedWithdrawalWaitingPeriod: Sender is not the withdrawer"
        );
        require(
            block.timestamp > queuedWithdrawals[withdrawalRoot].initTimestamp,
            "InvestmentManager.startQueuedWithdrawalWaitingPeriod: Stake may still be subject to slashing based on new tasks. Wait to set stakeInactiveAfter."
        );
        //they can only unlock after a withdrawal waiting period or after they are claiming their stake is inactive
        queuedWithdrawals[withdrawalRoot].unlockTimestamp = max((uint32(block.timestamp) + WITHDRAWAL_WAITING_PERIOD), stakeInactiveAfter);
    }

    /**
     * @notice Used to complete a queued withdraw in the given token and shareAmount from each of the respective given strategies,
     * that was initiated by 'depositor'. The 'withdrawer' address is looked up in storage.
     */
    function completeQueuedWithdrawal(QueuedWithdrawal calldata queuedWithdrawal, bool receiveAsTokens)
        external
        whenNotPaused
        // check that the address that the staker *was delegated to* – at the time that they queued the withdrawal – is not frozen
        onlyNotFrozen(queuedWithdrawal.delegatedAddress)
        nonReentrant
    {
        // find the withdrawalRoot
        bytes32 withdrawalRoot = calculateWithdrawalRoot(queuedWithdrawal);
        // copy storage to memory
        WithdrawalStorage memory withdrawalStorageCopy = queuedWithdrawals[withdrawalRoot];

        // verify that the queued withdrawal actually exists
        require(
            withdrawalStorageCopy.unlockTimestamp != 0,
            "InvestmentManager.completeQueuedWithdrawal: withdrawal does not exist"
        );

        require(
            uint32(block.timestamp) >= withdrawalStorageCopy.unlockTimestamp
                || (queuedWithdrawal.delegatedAddress == address(0)),
            "InvestmentManager.completeQueuedWithdrawal: withdrawal waiting period has not yet passed and depositor was delegated when withdrawal initiated"
        );

        // TODO: add testing coverage for this
        require(
            msg.sender == queuedWithdrawal.withdrawerAndNonce.withdrawer,
            "InvestmentManager.completeQueuedWithdrawal: only specified withdrawer can complete a queued withdrawal"
        );

        // reset the storage slot in mapping of queued withdrawals
        delete queuedWithdrawals[withdrawalRoot];

        // store length for gas savings
        uint256 strategiesLength = queuedWithdrawal.strategies.length;
        // if the withdrawer has flagged to receive the funds as tokens, withdraw from strategies
        if (receiveAsTokens) {
            // actually withdraw the funds
            for (uint256 i = 0; i < strategiesLength;) {
                // tell the strategy to send the appropriate amount of funds to the depositor
                queuedWithdrawal.strategies[i].withdraw(
                    withdrawalStorageCopy.withdrawer, queuedWithdrawal.tokens[i], queuedWithdrawal.shares[i]
                );
                unchecked {
                    ++i;
                }
            }
        } else {
            // else increase their shares
            for (uint256 i = 0; i < strategiesLength;) {
                _addShares(withdrawalStorageCopy.withdrawer, queuedWithdrawal.strategies[i], queuedWithdrawal.shares[i]);
                unchecked {
                    ++i;
                }
            }
        }

        emit WithdrawalCompleted(queuedWithdrawal.depositor, withdrawalStorageCopy.withdrawer, withdrawalRoot);
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
        QueuedWithdrawal calldata queuedWithdrawal,
        bytes calldata data,
        IServiceManager slashingContract
    )
        external
    {
        // find the withdrawalRoot
        bytes32 withdrawalRoot = calculateWithdrawalRoot(queuedWithdrawal);
        // copy storage to memory
        WithdrawalStorage memory withdrawalStorageCopy = queuedWithdrawals[withdrawalRoot];

        // verify that the queued withdrawal actually exists
        require(
            withdrawalStorageCopy.unlockTimestamp != 0,
            "InvestmentManager.fraudproofQueuedWithdrawal: withdrawal does not exist"
        );

        //verify the withdrawer has already initiated the withdrawal waiting period 
        require(
            withdrawalStorageCopy.unlockTimestamp != QUEUED_WITHDRAWAL_INITIALIZED_VALUE,
            "InvestmentManager.fraudproofQueuedWithdrawal: withdrawal was been initialized, but waiting period hasn't begun"
        );
        // check that it is not too late to provide a fraudproof
        require(
            uint32(block.timestamp) < withdrawalStorageCopy.unlockTimestamp,
            "InvestmentManager.fraudproofQueuedWithdrawal: withdrawal waiting period has already passed"
        );

        address operator = queuedWithdrawal.delegatedAddress;

        require(
            slasher.canSlash(operator, address(slashingContract)),
            "InvestmentManager.fraudproofQueuedWithdrawal: Contract does not have rights to slash operator"
        );

        {
            /**
             * Verify that there is an ongoing task, created at or before the `initTimestamp` and that expires
             * strictly after the `unlockTimestamp` for this queued withdrawal
             */
            slashingContract.stakeWithdrawalVerification(
                data, withdrawalStorageCopy.initTimestamp, withdrawalStorageCopy.unlockTimestamp
            );
        }

        // set the withdrawer equal to address(0), allowing the slasher custody of the funds
        queuedWithdrawals[withdrawalRoot].withdrawer = address(0);
    }

    /**
     * @notice Slashes the shares of 'frozen' operator (or a staker delegated to one)
     * @param strategyIndexes is a list of the indices in `investorStrats[msg.sender]` that correspond to the strategies
     * for which `msg.sender` is withdrawing 100% of their shares
     * @dev strategies are removed from `investorStrats` by swapping the last entry with the entry to be removed, then
     * popping off the last entry in `investorStrats`. The simplest way to calculate the correct `strategyIndexes` to input
     * is to order the strategies *for which `msg.sender` is withdrawing 100% of their shares* from highest index in
     * `investorStrats` to lowest index
     */
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
    function slashQueuedWithdrawal(address recipient, QueuedWithdrawal calldata queuedWithdrawal)
        external
        whenNotPaused
        onlyOwner
        nonReentrant
    {
        // find the withdrawalRoot
        bytes32 withdrawalRoot = calculateWithdrawalRoot(queuedWithdrawal);

        // verify that the queued withdrawal actually exists
        require(
            queuedWithdrawals[withdrawalRoot].unlockTimestamp != 0,
            "InvestmentManager.slashQueuedWithdrawal: withdrawal does not exist"
        );

        // verify that *either* the queued withdrawal has been successfully challenged, *or* the `depositor` has been frozen
        require(
            queuedWithdrawals[withdrawalRoot].withdrawer == address(0) || slasher.isFrozen(queuedWithdrawal.depositor),
            "InvestmentManager.slashQueuedWithdrawal: withdrawal has not been successfully challenged or depositor is not frozen"
        );

        // reset the storage slot in mapping of queued withdrawals
        delete queuedWithdrawals[withdrawalRoot];

        uint256 strategiesLength = queuedWithdrawal.strategies.length;
        for (uint256 i = 0; i < strategiesLength;) {
            // tell the strategy to send the appropriate amount of funds to the recipient
            queuedWithdrawal.strategies[i].withdraw(recipient, queuedWithdrawal.tokens[i], queuedWithdrawal.shares[i]);
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
            // remove the strategy from the depositor's dynamic array of strategies
            _removeStrategyFromInvestorStrats(depositor, strategyIndex, strategy);

            // return true in the event that the strategy was removed from investorStrats[depositor]
            return true;
        }
        // return false in the event that the strategy was *not* removed from investorStrats[depositor]
        return false;
    }

    /**
     * @notice Removes `strategy` from `depositor`'s dynamic array of strategies, i.e. from `investorStrats[depositor]`
     * @dev the provided `strategyIndex` input is optimistically used to find the strategy quickly in the list. If the specified
     * index is incorrect, then we revert to a brute-force search.
     */
    function _removeStrategyFromInvestorStrats(address depositor, uint256 strategyIndex, IInvestmentStrategy strategy) internal {
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
    }

    /**
     * @notice If the `depositor` has no existing shares, then they can `undelegate` themselves.
     * This allows people a "hard reset" in their relationship with EigenLayer after withdrawing all of their stake.
     */
    function _undelegate(address depositor) internal {
        require(investorStrats[depositor].length == 0, "InvestmentManager._undelegate: depositor has active deposits");
        delegation.undelegate(depositor);
    }

    function max(uint32 x, uint32 y) internal pure returns (uint32) {
        return x > y ? x : y;
    }

    // VIEW FUNCTIONS

    /**
     * @notice Used to check if a queued withdrawal can be completed
     */
    function canCompleteQueuedWithdrawal(QueuedWithdrawal calldata queuedWithdrawal) external view returns (bool) {
        // find the withdrawalRoot
        bytes32 withdrawalRoot = calculateWithdrawalRoot(queuedWithdrawal);

        // verify that the queued withdrawal actually exists
        require(
            queuedWithdrawals[withdrawalRoot].unlockTimestamp != 0,
            "InvestmentManager.canCompleteQueuedWithdrawal: withdrawal does not exist"
        );

        if (slasher.isFrozen(queuedWithdrawal.delegatedAddress)) {
            return false;
        }

        return (
            uint32(block.timestamp) >= queuedWithdrawals[withdrawalRoot].unlockTimestamp
                || (queuedWithdrawal.delegatedAddress == address(0))
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

    function calculateWithdrawalRoot(QueuedWithdrawal memory queuedWithdrawal) public pure returns (bytes32) {
        return (
            keccak256(
                abi.encode(
                    queuedWithdrawal.strategies,
                    queuedWithdrawal.tokens,
                    queuedWithdrawal.shares,
                    queuedWithdrawal.depositor,
                    queuedWithdrawal.withdrawerAndNonce,
                    queuedWithdrawal.delegatedAddress
                )
            )
        );
    }
}
