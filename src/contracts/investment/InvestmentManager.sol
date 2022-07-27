// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "./InvestmentManagerStorage.sol";
import "../utils/ERC1155TokenReceiver.sol";
import "forge-std/Test.sol";


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
    OwnableUpgradeable,
    InvestmentManagerStorage,
    ERC1155TokenReceiver,
    DSTest
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

    modifier onlyNotSlashed(address staker) {
        require(!slashedStatus[staker], "staker has been slashed");
        if (delegation.isDelegator(staker)) {
            address operatorAddress = delegation.delegation(staker);
            require(!slashedStatus[operatorAddress], "operator has been slashed");
        }
        _;
    }

    constructor(
        IEigenLayrDelegation _delegation
    ) InvestmentManagerStorage(_delegation) {
        // TODO: uncomment for production use!
        //_disableInitializers();
    }




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
        ISlasher _slasher,
        address _governor,
        address _eigenLayrDepositContract
    ) external initializer {
        consensusLayerEthStrat = strategies[0];
        proofOfStakingEthStrat = strategies[1];
        _transferOwnership(_governor);
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
    ) external onlyNotSlashed(msg.sender) returns (uint256 shares) {
        shares = _depositIntoStrategy(depositor, strategy, token, amount);
        
        // increase delegated shares accordingly, if applicable
        if (delegation.isDelegator(msg.sender)) {
            address operatorAddress = delegation.delegation(msg.sender);
            
            delegation.increaseOperatorShares(
                operatorAddress,
                strategy,
                shares
            );

            IDelegationTerms dt = delegation.delegationTerms(operatorAddress);

            //Calls into operator's delegationTerms contract to update weights of individual delegator
            IInvestmentStrategy[] memory investorStrats = new IInvestmentStrategy[](1);
            uint[] memory investorShares = new uint[](1);
            investorStrats[0] = strategy;
            investorShares[0] = shares;
            dt.onDelegationReceived(msg.sender, investorStrats, investorShares);

        }
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
    ) external onlyNotSlashed(msg.sender) returns (uint256[] memory) {
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
        // increase delegated shares accordingly, if applicable
        if (delegation.isDelegator(msg.sender)) {
            address operatorAddress = delegation.delegation(msg.sender);
            delegation.increaseOperatorShares(
                operatorAddress,
                strategies,
                shares
            );
            IDelegationTerms dt = delegation.delegationTerms(operatorAddress);
            //Calls into operator's delegationTerms contract to update weights of individual delegator
            dt.onDelegationReceived(msg.sender, strategies, shares);
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
    ) external onlyNotSlashed(msg.sender) onlyNotDelegated(msg.sender) {
        _withdrawFromStrategy(
            msg.sender,
            strategyIndex,
            strategy,
            token,
            shareAmount
        );
        // decrease delegated shares accordingly, if applicable
        if (delegation.isDelegator(msg.sender)) {
            address operatorAddress = delegation.delegation(msg.sender);
            delegation.decreaseOperatorShares(
                operatorAddress,
                strategy,
                shareAmount
            );

            IDelegationTerms dt = delegation.delegationTerms(operatorAddress);
            //Calls into operator's delegationTerms contract to update weights of individual delegator

            IInvestmentStrategy[] memory investorStrats = new IInvestmentStrategy[](1);
            uint[] memory investorShares = new uint[](1);
            investorStrats[0] = strategy;
            investorShares[0] = shareAmount;

            dt.onDelegationWithdrawn(msg.sender,investorStrats, investorShares);

        }
    }

    /**
     * @notice Used by stakers to withdraw the given token and shareAmount from the given strategies.
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
    ) external onlyNotSlashed(msg.sender) onlyNotDelegated(msg.sender) {
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
        // decrease delegated shares accordingly, if applicable
        if (delegation.isDelegator(msg.sender)) {
            address operatorAddress = delegation.delegation(msg.sender);
            delegation.decreaseOperatorShares(
                operatorAddress,
                strategies,
                shareAmounts
            );
            IDelegationTerms dt = delegation.delegationTerms(operatorAddress);
            dt.onDelegationWithdrawn(msg.sender, strategies, shareAmounts);
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

    // decreases the shares that 'depositor' holds in 'strategy' by 'shareAmount'
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

            // pop off the last entry in the list of strategies
            investorStrats[depositor].pop();
            
            // return true in the event that the strategy was removed from investorStrats[depositor]
            return true;
        }
        // return false in the event that the strategy was *not* removed from investorStrats[depositor]
        return false;
    }

   // TODO: decide if we should force an update to the depositor's delegationTerms contract, if they are actively delegated.
    /**
     * @notice Called by a staker to queue a withdraw in the given token and shareAmount from each of the respective given strategies.
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
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        WithdrawerAndNonce memory withdrawerAndNonce
    ) external onlyNotSlashed(msg.sender) {
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
            abi.encode(
                strategies,
                tokens,
                shareAmounts,
                withdrawerAndNonce.nonce
            )
        );
        

        // enter a scoped block here so we can declare 'delegatedAddress' and have it be cleared ASAP
        // this solves a 'stack too deep' error on compilation
        {
            if (delegation.isDelegator(msg.sender)) {
                address operatorAddress = delegation.delegation(msg.sender);
                delegation.decreaseOperatorShares(
                    operatorAddress,
                    strategies,
                    shareAmounts
                );
            }
            //TODO: call into delegationTerms contract as well?
        }

        uint256 strategiesLength = strategies.length;
        for (uint256 i = 0; i < strategiesLength; ) {
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
            abi.encode(
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
    ) external onlyNotSlashed(depositor) {
        bytes32 withdrawalRoot = keccak256(
            abi.encode(
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

        // to ensure there can't be multiple withdrawals for the same withdrawal request
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
    /**
     @param repository of one middleware where depositer is still obligated to provide its service 
     */
    function fraudproofQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        address depositor,
        uint256 queuedWithdrawalNonce,
        bytes calldata data,
        IServiceFactory serviceFactory,
        IRepository repository
    ) external {
        bytes32 withdrawalRoot = keccak256(
            abi.encode(
                strategies,
                tokens,
                shareAmounts,
                queuedWithdrawalNonce
            )
        );
        WithdrawalStorage memory withdrawalStorage = queuedWithdrawals[depositor][withdrawalRoot];
        uint32 unlockTime = withdrawalStorage.latestFraudproofTimestamp + WITHDRAWAL_WAITING_PERIOD;
        
        /// CRITIC --- can it be replaced with  withdrawalStorage.initTimestamp? more gas optimized
        uint32 initTimestamp = queuedWithdrawals[depositor][withdrawalRoot].initTimestamp;

        require(initTimestamp > 0, "withdrawal does not exist");
        require(uint32(block.timestamp) < unlockTime, "withdrawal waiting period has already passed");


        address operator = delegation.delegation(depositor);

        require(
            slasher.canSlash(
                operator,
                serviceFactory,
                repository,
                repository.registry()
            ),
            "Contract does not have rights to slash operator"
        );

        {
            // ongoing task is still active at time when staker was finalizing undelegation
            // and, therefore, hasn't served its obligation.

            IServiceManager serviceManager = repository.serviceManager();

            serviceManager.stakeWithdrawalVerification(data, initTimestamp, unlockTime);

        }
        //update latestFraudproofTimestamp in storage, which resets the WITHDRAWAL_WAITING_PERIOD for the withdrawal
        queuedWithdrawals[depositor][withdrawalRoot]
            .latestFraudproofTimestamp = uint32(block.timestamp);
    }



    /**
     * @notice Used for slashing a certain operator
     */
    /**
     * @dev only Slasher contract can call this function
     */
    function slashOperator(
        address slashedOperator
    ) external {
        require(msg.sender == address(slasher), "Only Slasher");
        slashedStatus[slashedOperator] = true;
    }

    function slashShares(
        address slashedAddress,
        address recipient,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata strategyIndexes,
        uint256[] calldata shareAmounts
    ) external onlyOwner {
        require(hasBeenSlashed(slashedAddress), "account has not been slashed");

        uint256 strategyIndexIndex;
        uint256 strategiesLength = strategies.length;
        for (uint256 i = 0; i < strategiesLength; ) {
            // the internal function will return 'true' in the event the strategy was
            // removed from the slashedAddress's array of strategies -- i.e. investorStrats[slashedAddress]
            if (
                _removeShares(
                    slashedAddress,
                    strategyIndexes[strategyIndexIndex],
                    strategies[i],
                    shareAmounts[i]
                )
            ) {
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
        if (!delegation.isSelfOperator(slashedAddress)) {
            address delegatedAddress = delegation.delegation(slashedAddress);

            delegation.decreaseOperatorShares(
                delegatedAddress,
                strategies,
                shareAmounts
            );
        }
    }

    function slashQueuedWithdrawal(       
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        address slashedAddress,
        address recipient,
        uint96 queuedWithdrawalNonce
    ) external onlyOwner {
        require(hasBeenSlashed(slashedAddress), "account has not been slashed");

        bytes32 withdrawalRoot = keccak256(
            abi.encode(
                strategies,
                tokens,
                shareAmounts,
                queuedWithdrawalNonce
            )
        );
        WithdrawalStorage memory withdrawalStorage = queuedWithdrawals[slashedAddress][withdrawalRoot];
        require(
            withdrawalStorage.initTimestamp > 0,
            "withdrawal does not exist"
        );

        //reset the storage slot in mapping of queued withdrawals
        queuedWithdrawals[slashedAddress][withdrawalRoot] = WithdrawalStorage({
            initTimestamp: uint32(0),
            latestFraudproofTimestamp: uint32(0),
            withdrawer: address(0)
        });

        uint256 strategiesLength = strategies.length;
        for (uint256 i = 0; i < strategiesLength; ) {
            // tell the strategy to send the appropriate amount of funds to the recipient
            strategies[i].withdraw(recipient, tokens[i], shareAmounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    function resetSlashedStatus(address[] calldata slashedAddresses) external onlyOwner {
        for (uint256 i = 0; i < slashedAddresses.length; ) {
            slashedStatus[slashedAddresses[i]] = false;
            unchecked { ++i; }
        }
    }


    /**
     @notice This function is used for updating the tally of the shares associated with ETH 
             that has been deposited into the EigenLayer with the intention of that 
             ETH being directly staked in beacon chain using EigenLayer's withdrawal credentials.
     */ 
    function depositConsenusLayerEth(address depositor, uint256 amount)
        external
        onlyEigenLayrDepositContract
        returns (uint256)
    {
        // this will be a "HollowInvestmentStrategy"
        uint256 shares = consensusLayerEthStrat.deposit(IERC20(address(0)), amount);

        // if they dont have existing shares of this strategy, add it to their strats
        if (shares > 0 && investorStratShares[depositor][consensusLayerEthStrat] == 0) {
            investorStrats[depositor].push(consensusLayerEthStrat);
        }

        // record the ETH that has been staked by the depositor
        investorStratShares[depositor][consensusLayerEthStrat] += shares;

        // increase delegated shares accordingly, if applicable
        if (delegation.isDelegator(msg.sender)) {
            address delegatedAddress = delegation.delegation(msg.sender);
            delegation.increaseOperatorShares(
                delegatedAddress,
                consensusLayerEthStrat,
                shares
            );
            //TODO: call into delegationTerms contract as well?
        }

        return shares;
    }


    /**
     @notice This function is used for updating the tally of the shares associated with ETH 
             that has been deposited into the EigenLayer with the intention of that 
             ETH being directly staked in beacon chain via a liquid staking service and then 
             investing the liquid token in investment strategies for engaging in DeFi.
     */ 
    function depositProofOfStakingEth(address depositor, uint256 amount)
        external
        onlyEigenLayrDepositContract
        returns (uint256)
    {
        //this will be a "HollowInvestmentStrategy"
        uint256 shares = proofOfStakingEthStrat.deposit(IERC20(address(0)), amount);

        // if they dont have existing shares of this strategy, add it to their strats
        if (shares > 0 && investorStratShares[depositor][proofOfStakingEthStrat] == 0) {
            investorStrats[depositor].push(proofOfStakingEthStrat);
        }
        
        // record the proof of staking ETH that has been staked by the depositor
        investorStratShares[depositor][proofOfStakingEthStrat] += shares;

        // increase delegated shares accordingly, if applicable
        if (delegation.isDelegator(msg.sender)) {
            address delegatedAddress = delegation.delegation(msg.sender);
            delegation.increaseOperatorShares(
                delegatedAddress,
                proofOfStakingEthStrat,
                shares
            );
            //TODO: call into delegationTerms contract as well?
        }

        return shares;
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
     * @notice get the underlying-denominated value of shares in specified investment strategies
     */
    function getUnderlyingValueOfStrategyShares(
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
            stake += strats[i].sharesToUnderlying(shares[i]);
            unchecked {
                ++i;
            }
        }
        return stake;
    }

    function getUnderlyingValueOfStrategySharesView(
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
            stake += strats[i].sharesToUnderlyingView(shares[i]);
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

    function hasBeenSlashed(address staker) public view returns (bool) {
        if (slashedStatus[staker]) {
            return true;
        } else if (delegation.isDelegator(staker)) {
            address operatorAddress = delegation.delegation(staker);
            return(slashedStatus[operatorAddress]);
        } else {
            return false;
        }
    }
}
