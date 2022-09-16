// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../utils/Pausable.sol";
import "./InvestmentManagerStorage.sol";
import "../interfaces/IServiceManager.sol";
// import "forge-std/Test.sol";

/**
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

    event WithdrawalQueued(address indexed depositor, address indexed withdrawer, bytes32 withdrawalRoot);
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
        // TODO: uncomment for production use!
        //_disableInitializers();
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Initializes the investment manager contract with a given set of strategies
     * and slashing rules.
     */
    /**
     * @param _slasher is the set of slashing rules to be used for the strategies associated with
     * this investment manager contract
     */
    function initialize(ISlasher _slasher, IPauserRegistry pauserRegistry, address _governor) external initializer {
        _transferOwnership(_governor);
        slasher = _slasher;

        _initializePauser(pauserRegistry);
    }
    /**
     * @notice used for investing a depositor's asset into the specified strategy in the
     * behalf of the depositor
     */
    /**
     * @param depositor is the address of the user who is investing assets into specified strategy,
     * @param strategy is the specified strategy where investment is to be made,
     * @param token is the denomination in which the investment is to be made,
     * @param amount is the amount of token to be invested in the strategy by the depositor
     */
    /**
     * @dev this function is called when a user stakes ETH for the purpose of depositing
     * into liquid staking first, use the associated liquid stake token for providing
     * validation service to EigenLayr and invest the token in DeFi. For more details,
     * see EigenLayrDeposit.sol.
     */

    function depositIntoStrategy(address depositor, IInvestmentStrategy strategy, IERC20 token, uint256 amount)
        external
        onlyNotFrozen(msg.sender)
        nonReentrant
        returns (uint256 shares)
    {
        shares = _depositIntoStrategy(depositor, strategy, token, amount);
    }

    /**
     * @notice Used to withdraw the given token and shareAmount from the given strategy.
     */
    /**
     * @dev Only those stakers who have notified the system that they want to undelegate
     * from the system, via calling commitUndelegation in EigenLayrDelegation.sol, can
     * call this function.
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
        uint256[] calldata shareAmounts,
        WithdrawerAndNonce calldata withdrawerAndNonce
    )
        external
        whenNotPaused
        onlyNotFrozen(msg.sender)
        nonReentrant
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

        bytes32 withdrawalRoot = calculateWithdrawalRoot(strategies, tokens, shareAmounts, withdrawerAndNonce);

        // modify delegated shares accordingly, if applicable
        delegation.decreaseDelegatedShares(msg.sender, strategies, shareAmounts);

        uint256 strategiesLength = strategies.length;
        for (uint256 i = 0; i < strategiesLength;) {
            // the internal function will return 'true' in the event the strategy was
            // removed from the depositor's array of strategies -- i.e. investorStrats[depositor]

            if (_removeShares(msg.sender, strategyIndexes[strategyIndexIndex], strategies[i], shareAmounts[i])) {
                unchecked {
                    ++strategyIndexIndex;
                }
            }

            //increment the loop
            unchecked {
                ++i;
            }
        }

        //update storage in mapping of queued withdrawals
        queuedWithdrawals[msg.sender][withdrawalRoot] = WithdrawalStorage({
            initTimestamp: uint32(block.timestamp),
            withdrawer: withdrawerAndNonce.withdrawer,
            unlockTimestamp: (uint32(block.timestamp) + WITHDRAWAL_WAITING_PERIOD)
        });

        emit WithdrawalQueued(msg.sender, withdrawerAndNonce.withdrawer, withdrawalRoot);
    }

    /**
     * @notice Used to complete a queued withdraw in the given token and shareAmount from each of the respective given strategies,
     * that was initiated by 'depositor'. The 'withdrawer' address is looked up in storage.
     */
    function completeQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        address depositor,
        WithdrawerAndNonce calldata withdrawerAndNonce
    )
        external
        whenNotPaused
        onlyNotFrozen(depositor)
        nonReentrant
    {
        // find the withdrawalRoot
        bytes32 withdrawalRoot = calculateWithdrawalRoot(strategies, tokens, shareAmounts, withdrawerAndNonce);
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

        //reset the storage slot in mapping of queued withdrawals
        delete queuedWithdrawals[depositor][withdrawalRoot];

        // actually withdraw the funds
        uint256 strategiesLength = strategies.length;
        for (uint256 i = 0; i < strategiesLength;) {
            // tell the strategy to send the appropriate amount of funds to the depositor
            strategies[i].withdraw(withdrawalStorageCopy.withdrawer, tokens[i], shareAmounts[i]);
            unchecked {
                ++i;
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
    function fraudproofQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        address depositor,
        WithdrawerAndNonce calldata withdrawerAndNonce,
        bytes calldata data,
        IServiceManager slashingContract
    )
        external
    {
        // find the withdrawalRoot
        bytes32 withdrawalRoot = calculateWithdrawalRoot(strategies, tokens, shareAmounts, withdrawerAndNonce);
        // copy storage to memory
        WithdrawalStorage memory withdrawalStorageCopy = queuedWithdrawals[depositor][withdrawalRoot];

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

        // update unlockTimestamp in storage, which resets the WITHDRAWAL_WAITING_PERIOD for the withdrawal
        queuedWithdrawals[depositor][withdrawalRoot].unlockTimestamp =
            uint32(block.timestamp) + WITHDRAWAL_WAITING_PERIOD;
    }

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

    function slashQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        address slashedAddress,
        address recipient,
        WithdrawerAndNonce calldata withdrawerAndNonce
    )
        external
        whenNotPaused
        onlyOwner
        onlyFrozen(slashedAddress)
        nonReentrant
    {
        // find the withdrawalRoot
        bytes32 withdrawalRoot = calculateWithdrawalRoot(strategies, tokens, shareAmounts, withdrawerAndNonce);

        // verify that the queued withdrawal actually exists
        require(
            queuedWithdrawals[slashedAddress][withdrawalRoot].initTimestamp > 0,
            "InvestmentManager.slashQueuedWithdrawal: withdrawal does not exist"
        );

        // reset the storage slot in mapping of queued withdrawals
        delete queuedWithdrawals[slashedAddress][withdrawalRoot];

        uint256 strategiesLength = strategies.length;
        for (uint256 i = 0; i < strategiesLength;) {
            // tell the strategy to send the appropriate amount of funds to the recipient
            strategies[i].withdraw(recipient, tokens[i], shareAmounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    // INTERNAL FUNCTIONS

    function _depositIntoStrategy(address depositor, IInvestmentStrategy strategy, IERC20 token, uint256 amount)
        internal
        returns (uint256 shares)
    {
        // if they dont have existing shares of this strategy, add it to their strats
        if (investorStratShares[depositor][strategy] == 0) {
            require(
                investorStrats[depositor].length <= MAX_INVESTOR_STRATS_LENGTH,
                "InvestmentManager._depositIntoStrategy: deposit would exceed MAX_INVESTOR_STRATS_LENGTH"
            );
            investorStrats[depositor].push(strategy);
        }
        // transfer tokens from the sender to the strategy
        token.safeTransferFrom(msg.sender, address(strategy), amount);

        // deposit the assets into the specified strategy and get the equivalent amount of
        // shares in that strategy
        shares = strategy.deposit(token, amount);
        require(shares != 0, "InvestmentManager._depositIntoStrategy: shares should not be zero!");

        // add the returned shares to their existing shares for this strategy
        investorStratShares[depositor][strategy] += shares;

        // if applicable, increase delegated shares accordingly
        delegation.increaseDelegatedShares(depositor, strategy, shares);

        return shares;
    }

    // withdraws 'shareAmount' shares that 'depositor' holds in 'strategy', to their address
    // if the amount of shares represents all of the depositor's shares in said strategy,
    // then the strategy is removed from investorStrats[depositor] and 'true' is returned
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

    // decreases the shares that 'depositor' holds in 'strategy' by 'shareAmount'
    // if the amount of shares represents all of the depositor's shares in said strategy,
    // then the strategy is removed from investorStrats[depositor] and 'true' is returned
    function _removeShares(address depositor, uint256 strategyIndex, IInvestmentStrategy strategy, uint256 shareAmount)
        internal
        returns (bool)
    {
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
     * @notice get all details on the depositor's investments and shares
     */
    /**
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
