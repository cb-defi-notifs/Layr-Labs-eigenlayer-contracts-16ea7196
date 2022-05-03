// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../utils/Governed.sol";
import "../utils/Initializable.sol";
import "./InvestmentManagerStorage.sol";
import "../utils/ERC1155TokenReceiver.sol";

// TODO: withdrawals of consensus layer ETH?
/**
 * @notice This contract is for managing investments in different strategies. The main
 *         functionalities are:
 *            - adding and removing investment strategies that any delegator can invest into
 *            - enabling deposit of assets into specified investment strategy(s)
 *            - enabling removal of assets from specified investment strategy(s)
 *            - recording deposit of ETH into settlement layer
 *            - recording deposit of Eigen for securing EigenLayr
 *            - slashing of assets for permissioned strategies
 */
contract InvestmentManager is
    Initializable,
    Governed,
    InvestmentManagerStorage,
    ERC1155TokenReceiver
{
    event WithdrawalQueued(
        address indexed depositor,
        address indexed withdrawer,
        bytes32 withdrawalRoot
    );
    event WithdrawalCompleted(
        address indexed depositor,
        address indexed withdrawer,
        bytes32 withdrawalRoot
    );

    modifier onlyNotDelegated(address user) {
        require(
            delegation.isNotDelegated(user),
            "InvestmentManager: onlyNotDelegated"
        );
        _;
    }

    modifier onlyEigenLayrDepositContract() {
        require(
            msg.sender == eigenLayrDepositContract,
            "InvestmentManager: onlyEigenLayrDepositContract"
        );
        _;
    }

    constructor(
        IERC1155 _EIGEN,
        IEigenLayrDelegation _delegation,
        IServiceFactory _serviceFactory
    ) InvestmentManagerStorage(_EIGEN, _delegation, _serviceFactory) {}

    /**
     * @notice Initializes the investment manager contract with a given set of strategies
     *         and slashing rules.
     */
    /**
     * @param _slasher is the set of slashing rules to be used for the strategies associated with 
     *        this investment manager contract   
     */
    function initialize(
        IInvestmentStrategy[] memory strategies,
        Slasher _slasher,
        address _governor,
        address _eigenLayrDepositContract
    ) external initializer {
        consensusLayerEthStrat = strategies[0];
        proofOfStakingEthStrat = strategies[1];
        // make the sender who is initializing the investment manager as the governor
        _transferGovernor(_governor);
        slasher = _slasher;
        eigenLayrDepositContract = _eigenLayrDepositContract;
    }

    /**
     * @notice used for investing a depositor's asset into the specified strategy in the
     *         behalf of the depositor
     */
    /**
     * @param depositor is the address of the user who is investing assets into specified strategy,
     * @param strategy is the specified strategy where investment is to be made,
     * @param token is the denomination in which the investment is to be made,
     * @param amount is the amount of token to be invested in the strategy by the depositor
     */
    /**
     * @dev this function is called when a user stakes ETH for the purpose of depositing
     *      into liquid staking first, use the associated liquid stake token for providing
     *      validation service to EigenLayr and invest the token in DeFi. For more details,
     *      see EigenLayrDeposit.sol.
     */
    function depositIntoStrategy(
        address depositor,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 amount
    ) external returns (uint256 shares) {
        shares = _depositIntoStrategy(depositor, strategy, token, amount);
    }

    /**
     * @notice used for investing a depositor's assets into multiple specified strategy, in the
     *         behalf of the depositor, with each of the investment being done in terms of a
     *         specified token and their respective amount.
     */
    function depositIntoStrategies(
        address depositor,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata amounts
    ) external returns (uint256[] memory) {
        uint256 strategiesLength = strategies.length;
        uint256[] memory shares = new uint256[](strategiesLength);
        for (uint256 i = 0; i < strategiesLength; ) {
            shares[i] = _depositIntoStrategy(
                depositor,
                strategies[i],
                tokens[i],
                amounts[i]
            );
            unchecked {
                ++i;
            }
        }
        return shares;
    }

    function _depositIntoStrategy(
        address depositor,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 amount
    ) internal returns (uint256 shares) {
        // if they dont have existing shares of this strategy, add it to their strats
        if (investorStratShares[depositor][strategy] == 0) {
            investorStrats[depositor].push(strategy);
        }

        // transfer tokens from the sender to the strategy
        bool success = token.transferFrom(
            msg.sender,
            address(strategy),
            amount
        );
        require(success, "failed to transfer token");

        // deposit the assets into the specified strategy and get the equivalent amount of
        // shares in that strategy
        shares = strategy.deposit(token, amount);

        // add the returned shares to their existing shares for this strategy
        investorStratShares[depositor][strategy] += shares;
    }

    /**
     * @notice Used to withdraw the given token and shareAmount from the given strategies.
     */
    /**
     * @dev Only those stakers who have notified the system that they want to undelegate
     *      from the system, via calling commitUndelegation in EigenLayrDelegation.sol, can
     *      call this function.
     */
    function withdrawFromStrategies(
        uint256[] calldata strategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts
    ) external onlyNotDelegated(msg.sender) {
        uint256 strategyIndexIndex;
        address depositor = msg.sender;

        uint256 strategiesLength = strategies.length;
        for (uint256 i = 0; i < strategiesLength; ) {
            // the internal function will return 'true' in the event the strategy was
            // removed from the depositor's array of strategies -- i.e. investorStrats[depositor]
            if (
                _withdrawFromStrategy(
                    depositor,
                    strategyIndexes[strategyIndexIndex],
                    strategies[i],
                    tokens[i],
                    shareAmounts[i]
                )
            ) {
                unchecked {
                    ++strategyIndexIndex;
                }
            }
            //increment the loop
            unchecked {
                ++i;
            }
        }
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
    ) internal returns (bool strategyRemovedFromArray) {
        strategyRemovedFromArray = _removeShares(
            depositor,
            strategyIndex,
            strategy,
            shareAmount
        );
        // tell the strategy to send the appropriate amount of funds to the depositor
        strategy.withdraw(depositor, token, shareAmount);
    }

    // reduces the shares that 'depositor' holds in 'strategy' by 'shareAmount'
    // if the amount of shares represents all of the depositor's shares in said strategy,
    // then the strategy is removed from investorStrats[depositor] and 'true' is returned
    function _removeShares(
        address depositor,
        uint256 strategyIndex,
        IInvestmentStrategy strategy,
        uint256 shareAmount
    ) internal returns (bool) {
        //check that the user has sufficient shares
        uint256 userShares = investorStratShares[depositor][strategy];
        require(shareAmount <= userShares, "shareAmount too high");
        //unchecked arithmetic since we just checked this above
        unchecked {
            userShares = userShares - shareAmount;
        }
        // subtract the shares from the depositor's existing shares for this strategy
        investorStratShares[depositor][strategy] = userShares;
        // if no existing shares, remove is from this investors strats
        if (investorStratShares[depositor][strategy] == 0) {
            // if the strategy matches with the strategy index provided
            if (investorStrats[depositor][strategyIndex] == strategy) {
                // replace the strategy with the last strategy in the list
                investorStrats[depositor][strategyIndex] = investorStrats[
                    depositor
                ][investorStrats[depositor].length - 1];
            } else {
                //loop through all of the strategies, find the right one, then replace
                uint256 stratsLength = investorStrats[depositor].length;

                for (uint256 j = 0; j < stratsLength; ) {
                    if (investorStrats[depositor][j] == strategy) {
                        //replace the strategy with the last strategy in the list
                        investorStrats[depositor][j] = investorStrats[
                            depositor
                        ][investorStrats[depositor].length - 1];
                        break;
                    }
                    unchecked {
                        ++j;
                    }
                }
            }

            // return true in the event that the strategy was removed from investorStrats[depositor]
            return true;
        }
        // return false in the event that the strategy was *not* removed from investorStrats[depositor]
        return false;
    }

   // TODO: decide if we should force an update to the depositor's delegationTerms contract, if they are actively delegated.
    /**
     * @notice Used to queue a withdraw in the given token and shareAmount from each of the respective given strategies.
     */
    /**
     * @dev Stakers will complete their withdrawal by calling the 'completeQueuedWithdrawal' function.
     *      User shares are decreased in this function, but the total number of shares in each strategy remains the same.
     *      The total number of shares is decremented in the 'completeQueuedWithdrawal' function instead, which is where
     *      the funds are actually sent to the user through use of the strategies' 'withdrawal' function. This ensures
     *      that the value per share reported by each strategy will remain consistent, and that the shares will continue
     *      to accrue gains during the enforced WITHDRAWAL_WAITING_PERIOD.
     */
    function queueWithdrawal(
        uint256[] calldata strategyIndexes,
        uint256[] calldata operatorStrategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        WithdrawerAndNonce memory withdrawerAndNonce
    ) external {
        require(
            withdrawerAndNonce.nonce == numWithdrawalsQueued[msg.sender],
            "provided nonce incorrect"
        );
        // increment the numWithdrawalsQueued of the sender
        unchecked {
            ++numWithdrawalsQueued[msg.sender];
        }
        uint256 strategyIndexIndex;

        bytes32 withdrawalRoot = keccak256(
            abi.encodePacked(
                strategies,
                tokens,
                shareAmounts,
                withdrawerAndNonce.nonce
            )
        );

        // enter a scoped block here so we can declare 'delegatedAddress' and have it be cleared ASAP
        // this solves a 'stack too deep' error on compilation
        {
            address delegatedAddress = delegation.delegation(msg.sender);
            if (delegatedAddress != msg.sender) {
                delegation.reduceOperatorShares(
                    delegatedAddress,
                    strategies,
                    shareAmounts
                );
            }
        }

        //TODO: take this nearly identically duplicated code and move it into a function
        // had to check against this rather than store it to solve 'stack too deep' error
        // uint256 strategiesLength = strategies.length;
        for (uint256 i = 0; i < strategies.length; ) {
            // the internal function will return 'true' in the event the strategy was
            // removed from the depositor's array of strategies -- i.e. investorStrats[depositor]
            if (
                _removeShares(
                    msg.sender,
                    strategyIndexes[strategyIndexIndex],
                    strategies[i],
                    shareAmounts[i]
                )
            ) {
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
            latestFraudproofTimestamp: uint32(block.timestamp),
            withdrawer: withdrawerAndNonce.withdrawer
        });

        emit WithdrawalQueued(
            msg.sender,
            withdrawerAndNonce.withdrawer,
            withdrawalRoot
        );
    }

    /**
     * @notice Used to check if a queued withdrawal can be completed
     */
    function canCompleteQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        address depositor,
        uint96 queuedWithdrawalNonce
    ) external view returns (bool) {
        bytes32 withdrawalRoot = keccak256(
            abi.encodePacked(
                strategies,
                tokens,
                shareAmounts,
                queuedWithdrawalNonce
            )
        );
        WithdrawalStorage memory withdrawalStorage = queuedWithdrawals[
            depositor
        ][withdrawalRoot];
        uint32 unlockTime = withdrawalStorage.latestFraudproofTimestamp +
            WITHDRAWAL_WAITING_PERIOD;
        require(
            withdrawalStorage.initTimestamp > 0,
            "withdrawal does not exist"
        );
        return (uint32(block.timestamp) >= unlockTime ||
            delegation.isNotDelegated(depositor));
    }

    //TODO: add something related to slashing for queued withdrawals
    /**
     * @notice Used to complete a queued withdraw in the given token and shareAmount from each of the respective given strategies,
     *          that was initiated by 'depositor'. The 'withdrawer' address is looked up in storage.
     */
    function completeQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        address depositor,
        uint96 queuedWithdrawalNonce
    ) external {
        bytes32 withdrawalRoot = keccak256(
            abi.encodePacked(
                strategies,
                tokens,
                shareAmounts,
                queuedWithdrawalNonce
            )
        );
        WithdrawalStorage memory withdrawalStorage = queuedWithdrawals[
            depositor
        ][withdrawalRoot];
        uint32 unlockTime = withdrawalStorage.latestFraudproofTimestamp +
            WITHDRAWAL_WAITING_PERIOD;
        address withdrawer = withdrawalStorage.withdrawer;
        require(
            withdrawalStorage.initTimestamp > 0,
            "withdrawal does not exist"
        );
        require(
            uint32(block.timestamp) >= unlockTime ||
                delegation.isNotDelegated(depositor),
            "withdrawal waiting period has not yet passed and depositor is still delegated"
        );

        //reset the storage slot in mapping of queued withdrawals
        queuedWithdrawals[depositor][withdrawalRoot] = WithdrawalStorage({
            initTimestamp: uint32(0),
            latestFraudproofTimestamp: uint32(0),
            withdrawer: address(0)
        });

        uint256 strategiesLength = strategies.length;
        for (uint256 i = 0; i < strategiesLength; ) {
            // tell the strategy to send the appropriate amount of funds to the depositor
            strategies[i].withdraw(withdrawer, tokens[i], shareAmounts[i]);
            unchecked {
                ++i;
            }
        }

        emit WithdrawalCompleted(depositor, withdrawer, withdrawalRoot);
    }

    /**
     * @notice Used prove that the funds to be withdrawn in a queued withdrawal are still at stake in an active query.
     *         The result is resetting the WITHDRAWAL_WAITING_PERIOD for the queued withdrawal.
     * @dev The fraudproof requires providing a repository contract and queryHash, corresponding to a query that was
     *      created at or before the time when the queued withdrawal was initiated, and expires prior to the time at
     *      which the withdrawal can currently be completed. A successful fraudproof sets the queued withdrawal's
     *      'latestFraudproofTimestamp' to the current UTC time, pushing back the unlock time for the funds to be withdrawn.
     */
    // TODO: de-duplicate this code and the code in EigenLayrDelegation's 'contestUndelegationCommit' function, if at all possible
    function fraudproofQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        address depositor,
        uint256 queuedWithdrawalNonce,
        bytes32 serviceObjectHash,
        IServiceFactory serviceFactory,
        IRepository repository,
        IRegistrationManager registrationManager
    ) external {
        bytes32 withdrawalRoot = keccak256(
            abi.encodePacked(
                strategies,
                tokens,
                shareAmounts,
                queuedWithdrawalNonce
            )
        );
        WithdrawalStorage memory withdrawalStorage = queuedWithdrawals[
            depositor
        ][withdrawalRoot];
        uint32 unlockTime = withdrawalStorage.latestFraudproofTimestamp +
            WITHDRAWAL_WAITING_PERIOD;
        uint32 initTimestamp = queuedWithdrawals[depositor][withdrawalRoot]
            .initTimestamp;
        require(initTimestamp > 0, "withdrawal does not exist");
        require(
            uint32(block.timestamp) < unlockTime,
            "withdrawal waiting period has already passed"
        );

        address operator = delegation.delegation(depositor);

        require(
            slasher.canSlash(
                operator,
                serviceFactory,
                repository,
                registrationManager
            ),
            "Contract does not have rights to prevent undelegation"
        );

        IServiceManager serviceManager = repository.serviceManager();

        // ongoing serviceObject is still active at time when staker was finalizing undelegation
        // and, therefore, hasn't served its obligation.
        require(
            initTimestamp >
                serviceManager.getServiceObjectCreationTime(
                    serviceObjectHash
                ) &&
                unlockTime <
                serviceManager.getServiceObjectExpiry(serviceObjectHash),
            "serviceObject does not meet requirements"
        );

        //update latestFraudproofTimestamp in storage, which resets the WITHDRAWAL_WAITING_PERIOD for the withdrawal
        queuedWithdrawals[depositor][withdrawalRoot]
            .latestFraudproofTimestamp = uint32(block.timestamp);
    }

    /**
     * @notice Used to withdraw the given token and shareAmount from the given strategy.
     */
    /**
     * @dev Only those stakers who have notified the system that they want to undelegate
     *      from the system, via calling commitUndelegation in EigenLayrDelegation.sol, can
     *      call this function.
     */
    // CRITIC:     a staker can get its asset back before finalizeUndelegation. Therefore,
    //             what is the incentive for calling finalizeUndelegation and starting off
    //             the challenge period when the staker can get its asset back before
    //             fulfilling its obligations. More details in slack.
    function withdrawFromStrategy(
        uint256 strategyIndex,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 shareAmount
    ) external onlyNotDelegated(msg.sender) {
        _withdrawFromStrategy(
            msg.sender,
            strategyIndex,
            strategy,
            token,
            shareAmount
        );
    }

    /**
     * @notice Used for slashing a certain user and transferring the slashed assets to
     *         the a certain recipient.
     */
    /**
     * @dev only Slasher contract can call this function
     */
    function slashShares(
        address slashed,
        address recipient,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata strategyIndexes,
        uint256[] calldata shareAmounts,
        uint256 maxSlashedAmount
    ) external {
        require(msg.sender == address(slasher), "Only Slasher");

        uint256 strategyIndexIndex;
        uint256 slashedAmount;
        for (uint256 i = 0; i < strategies.length; ) {
            // add the value of the slashed shares to the total amount slashed
            slashedAmount += strategies[i].underlyingEthValueOfShares(
                shareAmounts[i]
            );

            // the internal function will return 'true' in the event the strategy was
            // removed from the depositor's array of strategies -- i.e. investorStrats[depositor]
            if (
                _removeShares(
                    slashed,
                    strategyIndexes[strategyIndexIndex],
                    strategies[i],
                    shareAmounts[i]
                )
            ) {
                unchecked {
                    ++strategyIndexIndex;
                }
            }

            // add investor strats to that of recipient if it has not invested in this strategy yet
            if (investorStratShares[recipient][strategies[i]] == 0) {
                investorStrats[recipient].push(strategies[i]);
            }

            // add the slashed shares to that of the recipient
            investorStratShares[recipient][strategies[i]] += shareAmounts[i];

            // increment the loop
            unchecked {
                ++i;
            }
        }

        require(slashedAmount <= maxSlashedAmount, "excessive slashing");
    }

    function depositConsenusLayerEth(address depositor, uint256 amount)
        external
        onlyEigenLayrDepositContract
        returns (uint256)
    {
        //this will be a "HollowInvestmentStrategy"
        uint256 shares = consensusLayerEthStrat.deposit(IERC20(address(0)), amount);

        // record the ETH that has been staked by the depositor
        investorStratShares[depositor][consensusLayerEthStrat] += shares;

        return shares;
    }

    function depositProofOfStakingEth(address depositor, uint256 amount)
        external
        onlyEigenLayrDepositContract
        returns (uint256)
    {
        //this will be a "HollowInvestmentStrategy"
        uint256 shares = proofOfStakingEthStrat.deposit(IERC20(address(0)), amount);

        // record the proof of staking ETH that has been staked by the depositor
        investorStratShares[depositor][proofOfStakingEthStrat] += shares;

        return shares;
    }

    //returns depositor's new eigenBalance
    /**
    /// @notice Used for staking Eigen in EigenLayr.
     */
    function depositEigen(uint256 amount) external returns (uint256) {
        EIGEN.safeTransferFrom(
            msg.sender,
            address(this),
            eigenTokenId,
            amount,
            ""
        );
        uint256 deposited = eigenDeposited[msg.sender];
        totalEigenStaked = (totalEigenStaked + amount) - deposited;

        eigenDeposited[msg.sender] += amount;

        return (deposited + amount);
    }

    /**
     * @notice Used for withdrawing Eigen
     */
    function withdrawEigen(uint256 amount)
        external
        onlyNotDelegated(msg.sender)
    {
        eigenDeposited[msg.sender] -= amount;
        totalEigenStaked -= amount;
        EIGEN.safeTransferFrom(
            address(this),
            msg.sender,
            // fixed tokenId. TODO: make this flexible?
            0,
            amount,
            ""
        );
    }

    /**
     * @notice gets depositor's strategies
     */
    function getStrategies(address depositor)
        external
        view
        returns (IInvestmentStrategy[] memory)
    {
        return investorStrats[depositor];
    }

    /**
     * @notice gets depositor's shares in its strategies
     */
    function getStrategyShares(address depositor)
        external
        view
        returns (uint256[] memory)
    {
        uint256 strategiesLength = investorStrats[depositor].length;
        uint256[] memory shares = new uint256[](strategiesLength);

        for (uint256 i = 0; i < strategiesLength;) {
            shares[i] = investorStratShares[depositor][
                investorStrats[depositor][i]
            ];
            unchecked {
                ++i;
            }
        }

        return shares;
    }

    /**
     * @notice gets depositor's ETH that has been deposited directly to settlement layer
     */
    function getConsensusLayerEth(address depositor)
        external
        view
        returns (uint256)
    {
        return investorStratShares[depositor][consensusLayerEthStrat];
    }

    function getProofOfStakingEth(address depositor)
        external
        view
        returns (uint256)
    {
        return investorStratShares[depositor][proofOfStakingEthStrat];
    }

    /**
     * @notice gets depositor's Eigen that has been deposited
     */
    function getEigen(address depositor) external view returns (uint256) {
        return eigenDeposited[depositor];
    }

    /**
     * @notice get all details on the depositor's investments and shares
     */
    /**
     * @return (depositor's strategies, shares in these strategies)
     */
    function getDeposits(address depositor)
        external
        view
        returns (
            IInvestmentStrategy[] memory,
            uint256[] memory
        )
    {
        uint256 strategiesLength = investorStrats[depositor].length;
        uint256[] memory shares = new uint256[](strategiesLength);
        for (uint256 i = 0; i < strategiesLength;) {
            shares[i] = investorStratShares[depositor][
                investorStrats[depositor][i]
            ];
            unchecked {
                ++i;
            }
        }
        return (
            investorStrats[depositor],
            shares
        );
    }

    /**
     * @notice get the ETH-denominated value of shares in specified investment strategies
     */
    function getUnderlyingEthOfStrategyShares(
        IInvestmentStrategy[] calldata strats,
        uint256[] calldata shares
    ) external returns (uint256) {
        uint256 stake;
        uint256 numStrats = strats.length;
        require(
            numStrats == shares.length,
            "shares and strats must be same length"
        );

        // for all strats find uderlying eth value of shares
        for (uint256 i = 0; i < numStrats;) {
            stake += strats[i].underlyingEthValueOfShares(shares[i]);
            unchecked {
                ++i;
            }
        }
        return stake;
    }

    function getUnderlyingEthOfStrategySharesView(
        IInvestmentStrategy[] calldata strats,
        uint256[] calldata shares
    ) external view returns (uint256) {
        uint256 stake;
        uint256 numStrats = strats.length;
        require(
            numStrats == shares.length,
            "shares and strats must be same length"
        );
        // for all strats find uderlying eth value of shares
        for (uint256 i = 0; i < numStrats;) {
            stake += strats[i].underlyingEthValueOfSharesView(shares[i]);
            unchecked {
                ++i;
            }
        }
        return stake;
    }


    function investorStratsLength(address investor)
        external
        view
        returns (uint256)
    {
        return investorStrats[investor].length;
    }
}
