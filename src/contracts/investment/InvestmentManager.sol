// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IServiceFactory.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../utils/Governed.sol";
import "../utils/Initializable.sol";
import "./storage/InvestmentManagerStorage.sol";
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
    IERC1155 public immutable EIGEN;
    IEigenLayrDelegation public immutable delegation;
    IServiceFactory public immutable serviceFactory;

    event WithdrawalQueued(address indexed depositor, address indexed withdrawer, bytes32 withdrawalRoot);
    event WithdrawalCompleted(address indexed depositor, address indexed withdrawer, bytes32 withdrawalRoot);

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

    constructor(IERC1155 _EIGEN, IEigenLayrDelegation _delegation, IServiceFactory _serviceFactory) {
        EIGEN = _EIGEN;
        delegation = _delegation;
        serviceFactory = _serviceFactory;
    }

    /**
     * @notice Initializes the investment manager contract with a given set of strategies 
     *         and slashing rules. 
     */
    /**
     * @param strategies are the initial set of strategies
     * @param _slasher is the set of slashing rules to be used for the strategies associated with 
     *        this investment manager contract   
     */
    function initialize(
        IInvestmentStrategy[] memory strategies,
        address _slasher,
        address _governor,
        address _eigenLayrDepositContract
    ) external initializer {
        // make the sender who is initializing the investment manager as the governor
        _transferGovernor(_governor);
        slasher = _slasher;
        eigenLayrDepositContract = _eigenLayrDepositContract;

        // record the strategies as approved
        for (uint256 i = 0; i < strategies.length; i++) {
            stratApproved[strategies[i]] = true;
            if (!stratEverApproved[strategies[i]]) {
                stratEverApproved[strategies[i]] = true;
            }
        }
    }



    /**
     * @notice used for adding new investment strategies to the list of approved stratgeies
     *         of the investment manager contract 
     */ 
    /**
     * @param strategies are new strategies to be added
     */
    /**
     * @dev only the governor can add new strategies
     */ 
    function addInvestmentStrategies(IInvestmentStrategy[] calldata strategies)
        external
        onlyGovernor
    {
        for (uint256 i = 0; i < strategies.length; i++) { 
            stratApproved[strategies[i]] = true;

            if (!stratEverApproved[strategies[i]]) {
                stratEverApproved[strategies[i]] = true;
            }
        }
    }



    /**
     * @notice used for removing investment strategies from the list of approved stratgeies
     *         of the investment manager contract 
     */ 
    /**
     * @param strategies are strategies to be removed
     */
    /**
     * @dev only the governor can add new strategies
     */ 
    function removeInvestmentStrategies(
        IInvestmentStrategy[] calldata strategies
    ) external onlyGovernor {
        // set the approval status to false
        for (uint256 i = 0; i < strategies.length; i++) {
            stratApproved[strategies[i]] = false;
        }
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
    ) external payable returns (uint256 shares) {
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
    ) external payable returns (uint256[] memory) {
        uint256[] memory shares = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            shares[i] = _depositIntoStrategy(
                depositor,
                strategies[i],
                tokens[i],
                amounts[i]
            );
        }
        return shares;
    }



    function _depositIntoStrategy(
        address depositor,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 amount
    ) internal returns (uint256 shares) {
        require(
            stratApproved[strategy],
            "Can only deposit from approved strategies"
        );

        // if they dont have existing shares of this strategy, add it to their strats
        if (investorStratShares[depositor][strategy] == 0) {
            investorStrats[depositor].push(strategy);
        }

        // transfer tokens from the sender to the strategy
        _transferTokenOrEth(token, msg.sender, address(strategy), amount);

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
        for (uint256 i = 0; i < strategiesLength;) {
            require(
                stratEverApproved[strategies[i]],
                "Can only withdraw from approved strategies"
            );
            //check that the user has sufficient shares
            uint256 userShares = investorStratShares[depositor][strategies[i]];
            require(shareAmounts[i] <= userShares, "shareAmount too high");
            //unchecked arithmetic since we just checked this above
            unchecked {
                userShares = userShares - shareAmounts[i];
            }
            // subtract the shares from the depositor's existing shares for this strategy
            investorStratShares[depositor][strategies[i]] = userShares;

            // if no existing shares, remove this from this investors strats
            if (investorStratShares[depositor][strategies[i]] == 0) {
                // if the strategy matches with the strategy index provided
                if (
                    investorStrats[depositor][
                        strategyIndexes[strategyIndexIndex]
                    ] == strategies[i]
                ) {
                    // replace the strategy with the last strategy in the list
                    investorStrats[depositor][
                        strategyIndexes[strategyIndexIndex]
                    ] = investorStrats[depositor][
                        investorStrats[depositor].length - 1
                    ];
                } else {
                    //loop through all of the strategies, find the right one, then replace
                    uint256 stratsLength = investorStrats[depositor].length;

                    for (uint256 j = 0; j < stratsLength; ) {
                        if (investorStrats[depositor][j] == strategies[i]) {

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
                investorStrats[depositor].pop();
                strategyIndexIndex++;
            }

            // tell the strategy to send the appropriate amount of funds to the depositor
            strategies[i].withdraw(depositor, tokens[i], shareAmounts[i]);

            //increment the loop
            unchecked {
                ++i;
            }
        }
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
        address withdrawer
    ) external {
        uint256 strategyIndexIndex;

        //TODO: non-replicable (i.e. guaranteed unique) version of this. change it everywhere it's used
        bytes32 withdrawalRoot = keccak256(abi.encodePacked(strategies, tokens, shareAmounts));
        require(queuedWithdrawals[msg.sender][withdrawalRoot].initTimestamp == 0, "queued withdrawal already exists");

        // had to check against this directly rather than store it to solve 'stack too deep' error
        // address operator = delegation.delegation(msg.sender);
        // i.e. if the msg.sender is not a self-operator
        if (delegation.delegation(msg.sender) != msg.sender) {
            delegation.reduceOperatorShares(delegation.delegation(msg.sender), operatorStrategyIndexes, strategies, shareAmounts);
        }

        //TODO: take this nearly identically duplicated code and move it into a function
        // had to check against this rather than store it to solve 'stack too deep' error
        // uint256 strategiesLength = strategies.length;
        for (uint256 i = 0; i < strategies.length;) {
            require(
                stratEverApproved[strategies[i]],
                "Can only withdraw from approved strategies"
            );
            // //check that the user has sufficient shares
            // uint256 userShares = investorStratShares[msg.sender][strategies[i]];
            // require(shareAmounts[i] <= userShares, "shareAmount too high");
            // //unchecked arithmetic since we just checked this above
            // unchecked {
            //     userShares = userShares - shareAmounts[i];
            // }
            // subtract the shares from the msg.sender's existing shares for this strategy
            investorStratShares[msg.sender][strategies[i]] -= shareAmounts[i];

            // if no existing shares, remove this from this investors strats
            if (investorStratShares[msg.sender][strategies[i]] == 0) {
                // if the strategy matches with the strategy index provided
                if (
                    investorStrats[msg.sender][
                        strategyIndexes[strategyIndexIndex]
                    ] == strategies[i]
                ) {
                    // replace the strategy with the last strategy in the list
                    investorStrats[msg.sender][
                        strategyIndexes[strategyIndexIndex]
                    ] = investorStrats[msg.sender][
                        investorStrats[msg.sender].length - 1
                    ];
                } else {
                    //loop through all of the strategies, find the right one, then replace
                    uint256 stratsLength = investorStrats[msg.sender].length;

                    for (uint256 j = 0; j < stratsLength; ) {
                        if (investorStrats[msg.sender][j] == strategies[i]) {

                            //replace the strategy with the last strategy in the list
                            investorStrats[msg.sender][j] = investorStrats[
                                msg.sender
                            ][investorStrats[msg.sender].length - 1];
                            break;
                        }
                        unchecked {
                            ++j;
                        }
                    }
                }
                investorStrats[msg.sender].pop();
                unchecked{
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
            withdrawer: withdrawer
        });

        emit WithdrawalQueued(msg.sender, withdrawer, withdrawalRoot);
    }

    /**
     * @notice Used to check if a queued withdrawal can be completed
     */
    function canCompleteQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        address depositor
    ) external view returns (bool) {
        bytes32 withdrawalRoot = keccak256(abi.encodePacked(strategies, tokens, shareAmounts));
        WithdrawalStorage memory withdrawalStorage = queuedWithdrawals[depositor][withdrawalRoot];
        uint32 unlockTime = withdrawalStorage.latestFraudproofTimestamp + WITHDRAWAL_WAITING_PERIOD;
        require(withdrawalStorage.initTimestamp > 0, "withdrawal does not exist");
        return(uint32(block.timestamp) >= unlockTime || delegation.isNotDelegated(depositor));
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
        address depositor
    ) external {
        bytes32 withdrawalRoot = keccak256(abi.encodePacked(strategies, tokens, shareAmounts));
        WithdrawalStorage memory withdrawalStorage = queuedWithdrawals[depositor][withdrawalRoot];
        uint32 unlockTime = withdrawalStorage.latestFraudproofTimestamp + WITHDRAWAL_WAITING_PERIOD;
        address withdrawer = withdrawalStorage.withdrawer;
        require(withdrawalStorage.initTimestamp > 0, "withdrawal does not exist");
        require(
            uint32(block.timestamp) >= unlockTime || delegation.isNotDelegated(depositor),
            "withdrawal waiting period has not yet passed and depositor is still delegated"
        );

        //reset the storage slot in mapping of queued withdrawals
        queuedWithdrawals[depositor][withdrawalRoot] = WithdrawalStorage({
            initTimestamp: uint32(0),
            latestFraudproofTimestamp: uint32(0),
            withdrawer: address(0)
        });

        uint256 strategiesLength = strategies.length;
        for (uint256 i = 0; i < strategiesLength;) {
            // tell the strategy to send the appropriate amount of funds to the depositor
            strategies[i].withdraw(withdrawer, tokens[i], shareAmounts[i]);
        }

        emit WithdrawalCompleted(depositor, withdrawer, withdrawalRoot);
    }

    /**
     * @notice Used prove that the funds to be withdrawn in a queued withdrawal are still at stake in an active query.
     *         The result is resetting the WITHDRAWAL_WAITING_PERIOD for the queued withdrawal.
     * @dev The fraudproof requires providing a queryManager contract and queryHash, corresponding to a query that was
     *      created at or before the time when the queued withdrawal was initiated, and expires prior to the time at 
     *      which the withdrawal can currently be completed. A successful fraudproof sets the queued withdrawal's
     *      'latestFraudproofTimestamp' to the current UTC time, pushing back the unlock time for the funds to be withdrawn.
     */
    function fraudproofQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        address depositor,
        IQueryManager queryManager,
        bytes32 queryHash
    ) external {
        bytes32 withdrawalRoot = keccak256(abi.encodePacked(strategies, tokens, shareAmounts));
        WithdrawalStorage memory withdrawalStorage = queuedWithdrawals[depositor][withdrawalRoot];
        uint32 unlockTime = withdrawalStorage.latestFraudproofTimestamp + WITHDRAWAL_WAITING_PERIOD;
        uint32 initTimestamp = queuedWithdrawals[depositor][withdrawalRoot].initTimestamp;
        require(initTimestamp > 0, "withdrawal does not exist");
        require(uint32(block.timestamp) < unlockTime, "withdrawal waiting period has already passed");

        //TODO: Right now this is based on code from EigenLayrDelegation.sol. make this code non-duplicated
        address operator = delegation.delegation(depositor);

        //TODO: require that operator is registered to queryManager!
        require(
            serviceFactory.queryManagerExists(queryManager),
            "QueryManager was not deployed through factory"
        );

        // ongoing query was created at time when depositor queued the withdrawal
        // and  still active at time that they will currently be able to complete the withdrawal
        // therefore, the withdrawn funds are not expected to fully serve their obligation.
//TODO: fix this to work with new contract architecture
        // require(
        //     initTimestamp >=
        //         queryManager.getQueryCreationTime(queryHash) &&
        //         unlockTime <
        //         queryManager.getQueryCreationTime(queryHash) +
        //             queryManager.getQueryDuration(),
        //     "query must expire before unlockTime"
        // );

        //update latestFraudproofTimestamp in storage, which resets the WITHDRAWAL_WAITING_PERIOD for the withdrawal
        queuedWithdrawals[depositor][withdrawalRoot].latestFraudproofTimestamp = uint32(block.timestamp);
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
        address depositor = msg.sender;
        require(
            stratEverApproved[strategy],
            "Can only withdraw from approved strategies"
        );
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
            require(
                investorStrats[depositor][strategyIndex] == strategy,
                "Strategy index is incorrect"
            );
            // move the last element to the removed strategy's index, then shorten the array
            investorStrats[depositor][strategyIndex] = investorStrats[
                depositor
            ][investorStrats[depositor].length - 1];
            investorStrats[depositor].pop();
        }
        // tell the strategy to send the appropriate amount of funds to the depositor
        strategy.withdraw(
            depositor,
            token,
            shareAmount
        );
    }



    /**
     * @notice Used for slashing a certain user and transferring the slashed assets to
     *         the a certain recipient. 
     */
    /**
     * @dev only Slasher contract can call this function and slashing can be done only for 
     *      investment strategies that have permitted the Slasher contract to do slashing.
     *      More details on that in Slasher.sol.
     */ 
    function slashShares(
        address slashed,
        address recipient,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata strategyIndexes,
        uint256[] calldata shareAmounts,
        uint256 maxSlashedAmount
    ) external {
        require(msg.sender == slasher, "Only Slasher");

        uint256 strategyIndexIndex;
        uint256 slashedAmount;
        for (uint256 i = 0; i < strategies.length; i++) {
            require(
                stratEverApproved[strategies[i]],
                "Can only withdraw from approved strategies"
            );
            slashedAmount += strategies[i].underlyingEthValueOfShares(
                shareAmounts[i]
            );

            // subtract the shares for this strategy from that of slashed
            investorStratShares[slashed][strategies[i]] -= shareAmounts[i];

            // if no existing shares, remove this from slashed's investor strats
            if (investorStratShares[slashed][strategies[i]] == 0) {
                require(
                    investorStrats[slashed][
                        strategyIndexes[strategyIndexIndex]
                    ] == strategies[i],
                    "Strategy index is incorrect"
                );
                // move the last element to the removed strategy's index, then shorten the array
                investorStrats[slashed][
                    strategyIndexes[strategyIndexIndex]
                ] = investorStrats[slashed][investorStrats[slashed].length - 1];
                investorStrats[slashed].pop();
                strategyIndexIndex++;
            }

            // add investor strats to that of recipient if it has not invested in this strategy yet
            if (investorStratShares[recipient][strategies[i]] == 0) {
                investorStrats[recipient].push(strategies[i]);
            }

            // add the slashed shares to that of the recipient
            investorStratShares[recipient][strategies[i]] += shareAmounts[i];
        }

        require(slashedAmount <= maxSlashedAmount, "excessive slashing");
    }


    /**
     * @notice Used for setting the delegator's new ETH balance in the settlement layer
     */
    /**
     * @dev Caution that @param amount is the new ETH balance that the @param depositor wants
     *      and not the increment to the new balance.
     */ 
    function depositConsenusLayerEth(address depositor, uint256 amount)
        external
        onlyEigenLayrDepositContract
        returns (uint256)
    {
        // updating the total ETH staked into the settlement layer
        totalConsensusLayerEthStaked =
            totalConsensusLayerEthStaked +
            amount -
            consensusLayerEth[depositor];

        // record the ETH that has been staked by the depositor    
        consensusLayerEth[depositor] = amount;

        return amount;
    }

    //returns depositor's new eigenBalance
    /**
    /// @notice Used for staking Eigen in EigenLayr.
     */
    function depositEigen(uint256 amount)
        external
        returns (uint256)
    {
        EIGEN.safeTransferFrom(
            msg.sender,
            address(this),
            eigenTokenId,
            amount,
            ""
        );
        uint256 deposited = eigenDeposited[msg.sender];
        totalEigenStaked =
            (totalEigenStaked +
            amount) -
            deposited;

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
        uint256[] memory shares = new uint256[](
            investorStrats[depositor].length
        );

        for (uint256 i = 0; i < shares.length; i++) {
            shares[i] = investorStratShares[depositor][
                investorStrats[depositor][i]
            ];
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
        return consensusLayerEth[depositor];
    }


    /**
     * @notice gets depositor's Eigen that has been deposited
     */
    function getEigen(address depositor) external view returns (uint256) {
        return eigenDeposited[depositor];
    }


    /**
     * @notice get all details on the depositor's investments, shares, ETH and Eigen staked.
     */
    /**
     * @return (depositor's strategies, shares in these strategies, ETH staked, Eigen staked)
     */
    function getDeposits(address depositor)
        external
        view
        returns (
            IInvestmentStrategy[] memory,
            uint256[] memory,
            uint256,
            uint256
        )
    {
        uint256[] memory shares = new uint256[](
            investorStrats[depositor].length
        );
        for (uint256 i = 0; i < shares.length; i++) {
            shares[i] = investorStratShares[depositor][
                investorStrats[depositor][i]
            ];
        }
        return (
            investorStrats[depositor],
            shares,
            consensusLayerEth[depositor],
            eigenDeposited[depositor]
        );
    }


    /**
     * @notice get underlying sum of actual ETH staked into settlement layer and 
     *         and the ETH-denominated value of shares in various investment strategies 
     *         for the given depositor    
     */
    function getUnderlyingEthStaked(address depositor)
        external
        returns (uint256)
    {
        // actual ETH staked in settlement layer
        uint256 stake = consensusLayerEth[depositor];

        // for all strats find uderlying eth value of shares
        uint256 numStrats = investorStrats[depositor].length;
        for (uint256 i = 0; i < numStrats; i++) {
            IInvestmentStrategy strat = investorStrats[depositor][i];
            stake += strat.underlyingEthValueOfShares(
                investorStratShares[depositor][strat]
            );
        }

        return stake;
    }

    function getUnderlyingEthStakedView(address depositor)
        external
        view
        returns (uint256)
    {
        uint256 stake = consensusLayerEth[depositor];
        uint256 numStrats = investorStrats[depositor].length;
        // for all strats find uderlying eth value of shares
        for (uint256 i = 0; i < numStrats; i++) {
            IInvestmentStrategy strat = investorStrats[depositor][i];
            stake += strat.underlyingEthValueOfSharesView(
                investorStratShares[depositor][strat]
            );
        }
        return stake;
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
        for (uint256 i = 0; i < numStrats; i++) {
            stake += strats[i].underlyingEthValueOfShares(shares[i]);
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
        for (uint256 i = 0; i < numStrats; i++) {
            stake += strats[i].underlyingEthValueOfSharesView(shares[i]);
        }
        return stake;
    }


    function investorStratsLength(address investor) external view returns (uint256) {
        return investorStrats[investor].length;
    }

    

    /**
     * @notice used for transferring specified amount of specified token from the 
     *         sender to the receiver
     */
    function _transferTokenOrEth(
        IERC20 token,
        address sender,
        address receiver,
        uint256 amount
    ) internal {
        if (address(token) == ETH) {
            (bool success, ) = receiver.call{value: amount}("");
            require(success, "failed to transfer value");
        } else {
            bool success = token.transferFrom(sender, receiver, amount);
            require(success, "failed to transfer token");            
        }
    }
}
