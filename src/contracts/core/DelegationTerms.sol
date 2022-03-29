// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IDelegationTerms.sol";
import "../interfaces/IServiceFactory.sol";

// TODO: dealing with pending payments to the contract at time of deposit / delegation (or deciding this design is acceptable)

/**
 * @notice This contract specifies the delegation terms of a given operator. When any delegator
 *         wants to delegate its stake to the operator, it has to agree to the terms set in this
 *         delegator term of the operator. The contract specifies:
 *           - the operator's portion of the rewards,
 *           - each of the delegator's portion of the rewards,   
 *           - tokens that  middlewares can use for paying to the operator and its delegators, 
 *           - function for fee manager, associated with any middleware, to pay the rewards
 *           - functions for enabling operator and delegators to withdraw rewards 
 */
/**
 * @dev The Delegation Terms contract of an operator maintains a record of what fraction
 *      of the total reward each delegator of that operator is owed whenever the operator triggers
 *      a fee manager to pay the rewards for the service that was offered to that fee manager's
 *      middleware via EigenLayr. To understand how each delegator's rewards are allocated for each
 *      middleware, we have the following description:    
 *
 *          We define a round to be the instant where fee manager pays out the rewards to the delegators of this delegation term contract.
 *          Let there be n delegators with weightEth_{j,i} and weightEigen_{j,i} being the total ETH and Eigen that 
 *          has been delegated by j^th delegator at any round i. Suppose that at the round i, amount_i be the 
 *          cumulative reward that is being allocated to all the n delegators since round (i-1). Also let totalWeightEth_i 
 *          and totalWeightEigen_i are the total ETH and Eigen that been delegated by the  delegators 
 *          under this delegation term at round i, respectively. Let gammaEth and gammaEigen be the weights assigned 
 *          by the middleware for splitting the rewards between the ETH stakers and Eigen stakers, respectively. 
 *
 *          Then the reward that any j^th delegator is eligible for its ETH stake at round i is
 *                          
 *                                    (weightEth_{j,i} / totalWeightEth_i) *  amount_i *  gammaEth           
 *
 *          Then the reward that any j^th delegator is eligible for its Eigen stake at round i is
 *                          
 *                                    (weightEigen_{j,i} / totalWeightEigen_i) *  amount_i *  gammaEigen                                      
 *
 *          The operator maintains arrays  [r_{ETH,1}, r_{ETH,2}, ...] and 
 *          [r_{Eigen,1}, r_{Eigen,2}, ...] where 
 *
 *                                  r_{ETH,i} = r_{ETH,i} + (gammaEth *  amount_i/ totalWeightEth_i),
 *
 *                                  r_{Eigen,i} = r_{Eigen,i} + (gammaEigen *  amount_i/ totalWeightEigen_i).
 *
 *          If j^th delegator hasn't updated its stake in ETH or Eigen for the rounds i in [k_1,k_2], that is,
 *
 *                                  weightEth_{j,k_1} = weightEth_{j,k_1+1} = ... = weightEth_{j,k_2} = constEth,
 *                                  weightEigen_{j,k_1} = weightEigen_{j,k_1+1} = ... = weightEigen_{j,k_2} = constEigen,
 *
 *          then, total reward j^th delegator is eligible for the rounds in [k_1,k_2] is given by                                    
 *                 
 *                    [(r_{ETH,k_2} - r_{ETH,k_1} + 1) *  constETH] +  [(r_{Eigen,k_2} - r_{Eigen,k_1} + 1) *  constEigen]     
 *
 *          However, if the j^th delegator updates its ETH or Eigen delegated stake at any round i, then, the above     
 *          formula for j^th delegator's reward is not true as totalWeightEth_i or totalWeightEigen_i  
 *          also gets updated along with weightEth_{j,i} and weightEigen_{j,i}. So, before the delegator updates 
 *          its ETH or Eigen stake, it has to retrieve its reward. However, other delegators whose delegated ETH or 
 *          Eigen hasn't updated, they can continue to use the above formula.          
 */
contract DelegationTerms is IDelegationTerms {
    /// @notice Stored for each delegator that have accepted this delegation terms from the operator
    struct DelegatorStatus {
        // value of delegator's shares in different strategies in ETH
        uint112 weightEth;
        // total Eigen that delegator has delegated to the operator of this delegation contract
        uint112 weightEigen;
        // UTC timestamp at which the delegator last claimed their earnings. ensures delegators do not receive undue rewards
        uint32 lastClaimedRewards;
    }

    /**
     *  @notice Used for recording the multiplying factor that has to be multiplied with 
     *          delegator's delegated ETH and Eigen to obtain its actual rewards. 
     */
    /** 
     *  @dev To relate the fields of this struct with explanation at the top, "TokenPayment" 
     *       for any round k when the payment is being made from the fee manager, 
     *                   TokenPayment.earnedPerWeightAllTimeEth = r_{ETH,k}
     *                   TokenPayment.earnedPerWeightAllTimeEigen = r_{Eigen,k}.   
     *
     *       These multiplying factors r_{ETH,k} and r_{Eigen,k} can be also interpreted as the 
     *       cumulative earnings in a given token per delegated ETH and Eigen.    
     */ 
    struct TokenPayment {
        // multiplying factor for calculating the rewards due to ETH delegated to this operator
        uint112 earnedPerWeightAllTimeEth;
        // multiplying factor for calculating the rewards due to Eigen delegated to this operator
        uint112 earnedPerWeightAllTimeEigen;        
        //UTC timestamp at which the payment was received
        uint32 paymentTimestamp;
    }

    

    // sum of value in ETH of individual delegator's shares in different strategies 
    uint128 public totalWeightEth;
    // sum of total Eigen of individual delegators that have been delegated to the operator
    uint128 public totalWeightEigen;


    /// @notice mapping from token => list of payments to this contract
    /**  
     *  @dev To relate to the description given at the top, the TokenPayment[] array for each token 
     *       contains description of [r_{ETH,1}, r_{ETH,2}, ...] and [r_{Eigen,1}, r_{Eigen,2}, ...]
     */
    mapping(address => TokenPayment[]) public paymentsHistory;
    // mapping from delegator => weights + last timestamp that they claimed rewards
    mapping(address => DelegatorStatus) public delegatorStatus;
    // earnings to be withdrawn by the operator
    mapping(address => uint256) public operatorPendingEarnings;
    // list of tokens that can be actively used by middlewares for paying to this delegation terms contract
    address[] public paymentTokens;


    // CONSTANTS. scaling factor is ~1.8e19 -- being on the order of 1 ETH (1e18) helps ensure that
    //            ((amount * REWARD_SCALING) / totalWeightEth) is nonzero but also does not overflow
    uint256 internal constant REWARD_SCALING = 2**64;
    uint16 internal constant MAX_BIPS = 10000;
    //max number of payment tokens, for sanity's sake
    uint16 internal constant MAX_PAYMENT_TOKENS = 256;
    //portion of all earnings (in BIPS) retained by operator
    uint16 public operatorFeeBips;
    //maximum value to which 'operatorFeeBips' can be set by the operator
    uint16 internal immutable MAX_OPERATOR_FEE_BIPS;
    // operator for this delegation contract
    address public immutable operator;
    //important contracts -- used for access control
    IServiceFactory public immutable serviceFactory;
    address public immutable eigenLayrDelegation;
    //used for weighting of delegated ETH & EIGEN
    IInvestmentManager public immutable investmentManager;

    //NOTE: copied from 'DataLayrVoteWeigher.sol'
    //consensus layer ETH counts for 'consensusLayerPercent'/100 when compared to ETH deposited in the system itself
    uint256 public constant consensusLayerPercent = 10;

    // EVENTS
    event OperatorFeeBipsSet(uint16 previousValue, uint16 newValue);


    // MODIFIERS
    modifier onlyOperator() {
        require(msg.sender == operator, "onlyOperator");
        _;
    }

    modifier onlyDelegation() {
        require(msg.sender == eigenLayrDelegation, "only eigenLayrDelegation");
        _;
    }



    constructor(
        IInvestmentManager _investmentManager,
        address[] memory _paymentTokens,
        IServiceFactory _serviceFactory,
        address _eigenLayrDelegation,
        uint16 _MAX_OPERATOR_FEE_BIPS,
        uint16 _operatorFeeBips
    ){
        investmentManager = _investmentManager;
        //initialize operator as msg.sender
        operator = msg.sender;
        paymentTokens = _paymentTokens;
        serviceFactory = _serviceFactory;
        eigenLayrDelegation = _eigenLayrDelegation;
        require(_MAX_OPERATOR_FEE_BIPS <= MAX_BIPS, "MAX_OPERATOR_FEE_BIPS cannot be above MAX_BIPS");
        MAX_OPERATOR_FEE_BIPS = _MAX_OPERATOR_FEE_BIPS;
        _setOperatorFeeBips(_operatorFeeBips);
    }

    /// @notice sets the operatorFeeBips
    function setOperatorFeeBips(uint16 bips) external onlyOperator {
        _setOperatorFeeBips(bips);
    }

    /// @notice Add new payment token that can be used by a middleware to pay delegators
    ///         in this delegation terms contract.   
    function addPaymentToken(address token) external onlyOperator {
        require(paymentTokens.length < MAX_PAYMENT_TOKENS, "too many payment tokens");
        paymentTokens.push(token);
    }

    /// @notice Remove an existing payment token from the array of payment tokens
    function removePaymentToken(address token, uint256 currentIndexInArray) external onlyOperator {
        require(token == paymentTokens[currentIndexInArray], "incorrect array index supplied");
        //copy the last entry in the array to the index of the token to be removed, then pop the array
        paymentTokens[currentIndexInArray] = paymentTokens[paymentTokens.length - 1];
        paymentTokens.pop();
    }

    /**
     * @notice Used for operator to withdraw all its rewards
     */ 
    function operatorWithdrawal() external {
        uint256 length = paymentTokens.length;
        for (uint256 i; i < length;) {
            _operatorWithdraw(paymentTokens[i]);
            //if this overflows I will eat my shoe
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Used for transferring rewards accrued in a speciifc token
     */
    function _operatorWithdraw(address token) internal {
        uint256 pending = operatorPendingEarnings[token];
        operatorPendingEarnings[token] = 0;
        if (pending > 0) {
            IERC20(token).transfer(operator, pending);
        }
    }

    /** 
     * @notice  Fee manager of a middleware calls this function in order to update the rewards that 
     *          this operator and the delegators associated with it are eligible for because of their  
     *          service to that middleware.     
     */ 
    /** 
     * @param token is the ERC20 token in which the middlewares are paying its rewards for the service,
     * @param amount is the amount of ERC20 tokens that is being paid as rewards. 
     */
    function payForService(IERC20 token, uint256 amount) external payable {
        // determine the query manager associated with the fee manager
        IQueryManager queryManager = IFeeManager(msg.sender).queryManager();

        // only the fee manager can call this function
        require(msg.sender == address(queryManager.feeManager()), "only feeManagers");

        // check if the query manager exists
        require(serviceFactory.queryManagerExists(queryManager), "illegitimate queryManager");

        TokenPayment memory updatedEarnings;
        if (paymentsHistory[address(token)].length > 0) {
            // get the most recent payment made to the operator in this token
            updatedEarnings = paymentsHistory[address(token)][paymentsHistory[address(token)].length - 1];
        }

        // obtain the earning that the operator is eligible for out of the total rewards
        if (operatorFeeBips > 0) {
            uint256 operatorEarnings = (amount * operatorFeeBips) / MAX_BIPS;
            operatorPendingEarnings[address(token)] += operatorEarnings;
            // obtain the remaining reward after deducting the operator's part
            amount -= operatorEarnings;
        }

//TODO: improve this calculation
        /*
        // find the multiple of the amount earned by delegators holding EIGEN vs the amount earned by delegators holding ETH. this should be equal to:
        //          (fraction of amount going to EIGEN holders in the middleware)
        //          * (fraction of EIGEN in the middleware delegated to the operator of this contract)
        //          / (fraction of ETH in the middleware delegated to the operator of this contract)
        */
        //multiplier as a fraction of 1e18. i.e. we act as if 'multipleToEthHolders' is always 1e18 and then compare EIGEN holder earnings to that.
        uint256 multipleToEigenHolders = 1e18; //TODO: where to fetch this? this is initialized as 1e18 = EIGEN earns 50% of all middleware fees
        IQueryManager.Stake memory totalStake = queryManager.totalStake();
        IQueryManager.Stake memory operatorStake = queryManager.operatorStakes(operator);
        fractionToEigenHolders = (((fractionToEigenHolders * totalStake.eigenStaked) / operatorStake.eigenStaked) * totalStake.ethStaked / operatorStake.ethStaked);
        uint256 amountToEigenHolders = (amount * fractionToEigenHolders) / (fractionToEigenHolders + 1e18);
        //uint256 amountToEthHolders = amount - amountToEigenHolders

        // update the multiplying factors, scaled by REWARD_SCALING 
        updatedEarnings.earnedPerWeightAllTimeEth += uint112(((amount - amountToEigenHolders) * REWARD_SCALING) / totalWeightEth);
        updatedEarnings.earnedPerWeightAllTimeEigen += uint112((amountToEigenHolders * REWARD_SCALING) / totalWeightEigen);
        
        // update the timestamp for the last payment of the rewards
        updatedEarnings.paymentTimestamp = uint32(block.timestamp);

        // record the payment details
        paymentsHistory[address(token)].push(updatedEarnings);
    }


//NOTE: the logic in this function currently mimmics that in the 'weightOfEth' function
    /**
     * @notice Hook for receiving new delegation   
     */
    function onDelegationReceived(
        address delegator,
        IInvestmentStrategy[] memory investorStrats,
        uint256[] memory investorShares
    ) external onlyDelegation {
        DelegatorStatus memory delegatorUpdate;
        // get the ETH that has been staked by a delegator in the settlement layer (beacon chain) 
        uint256 weight = (investmentManager.getConsensusLayerEth(delegator) * consensusLayerPercent) / 100;
        uint256 investorStratsLength = investorStrats.length;
        for (uint256 i; i < investorStratsLength;) {
            // get the underlying ETH value of the shares
            // each investment strategy have their own description of ETH value per share.
            weight += investorStrats[i].underlyingEthValueOfShares(investorShares[i]);
            unchecked {
                ++i;
            }
        }
        delegatorUpdate.weightEth = uint112(weight);
        delegatorUpdate.weightEigen = uint112(weightOfEigen(delegator));
        delegatorUpdate.lastClaimedRewards = uint32(block.timestamp);
        totalWeightEth += delegatorUpdate.weightEth;
        totalWeightEigen += delegatorUpdate.weightEigen;
        //update storage at end
        delegatorStatus[delegator] = delegatorUpdate;
    }

//NOTE: currently this causes the delegator to lose any pending rewards
    /**
     * @notice Hook for withdrawing delegation   
     */
    function onDelegationWithdrawn(
        address delegator,
        IInvestmentStrategy[] memory,
        uint256[] memory
    ) external onlyDelegation {
        DelegatorStatus memory delegatorUpdate = delegatorStatus[delegator];
        totalWeightEth -= delegatorUpdate.weightEth;
        totalWeightEigen -= delegatorUpdate.weightEigen;
        delegatorUpdate.weightEth = 0;
        delegatorUpdate.weightEigen = 0;
        //update storage at end
        delegatorStatus[delegator] = delegatorUpdate;
    }

    /**
     * @notice Used by the delegator for withdrawing pending rewards for all active tokens that 
     *         has been accrued from the service provided to the middlewares via EigenLayr.
     */
    /**
     * @param indices are the locations in paymentsHistory to claim from.
     */ 
    function withdrawPendingRewards(uint32[] calldata indices) external {
        uint256 length = paymentTokens.length;
        require(indices.length == length, "incorrect input length");

        // getting the details on multiplying factor for the delegator and its last reward claim
        DelegatorStatus memory delegator = delegatorStatus[msg.sender];
        for (uint256 i; i < length;) {
            _withdrawPendingRewards(delegator, paymentTokens[i], indices[i]);
            unchecked {
                ++i;
            }
        }
        _updateDelegatorWeights(msg.sender);
    }


    /**
     * @notice Used by the delegator for withdrawing pending rewards for specified active tokens that 
     *         has been accrued from the service provided to the middlewares via EigenLayr. Pending  
     *         rewards are lost for other tokens!
     */
    /**
     * @param tokens is the list of active tokens for whom rewards are to claimed,
     * @param indices are the locations in paymentsHistory to claim from.
     */
    // CRITIC: should we have slight different name as it provided functionality to specify
    //         the tokens? 
    function withdrawPendingRewards(address[] calldata tokens, uint32[] calldata indices) external {
        uint256 length = tokens.length;
        require(indices.length == length, "incorrect input length");
        DelegatorStatus memory delegator = delegatorStatus[msg.sender];
        for (uint256 i; i < length;) {
            _withdrawPendingRewards(delegator, tokens[i], indices[i]);
            unchecked {
                ++i;
            }
        }
        _updateDelegatorWeights(msg.sender);
    }

    /// @notice internal function used both in 'setOperatorFeeBips' and the constructor
    function _setOperatorFeeBips(uint16 bips) internal {
        require(bips <= MAX_OPERATOR_FEE_BIPS, "setOperatorFeeBips: input too high");
        emit OperatorFeeBipsSet(operatorFeeBips, bips);
        operatorFeeBips = bips;
    }


    /**
     * @notice Used by delegator for updating its info in contract depending on its updated stake.   
     *         Delegator must withdraw pending rewards first, or else they will be lost!   
     */
    /**
     * @param user is the delegator that is updating its info.   
     */ 
    function _updateDelegatorWeights(address user) internal {
        // query delegator delails
        DelegatorStatus memory delegator = delegatorStatus[user];
        
        // update the multiplying weight for ETH delegated to this operator
        uint256 newWeight = weightOfEth(user);
        uint256 previousWeight = delegator.weightEth;
        // if weight has increased
        if (newWeight > previousWeight) {
            totalWeightEth += uint128(newWeight - previousWeight);
        // if weight has decreased
        } else if (newWeight < previousWeight) {
            totalWeightEth -= uint128(previousWeight - previousWeight);
        }
        delegator.weightEth = uint112(newWeight);


        // update the multiplying weight for Eigen delegated to this operator
        newWeight = weightOfEigen(user);
        previousWeight = delegator.weightEigen;
        // if weight has increased
        if (newWeight > previousWeight) {
            totalWeightEigen += uint128(newWeight - previousWeight);
        // if weight has decreased
        } else if (newWeight < previousWeight) {
            totalWeightEigen -= uint128(previousWeight - previousWeight);
        }
        delegator.weightEigen = uint112(newWeight);

        // update latest timestamp claimed
        if (block.timestamp > delegator.lastClaimedRewards) {
            delegator.lastClaimedRewards = uint32(block.timestamp);
        }

        //update delegator details 
        delegatorStatus[user] = delegator;
    }

    //withdraw pending rewards for a single token. **must update delegator's 'lastClaimedRewards' timestamp after invoking this**
    //combines _withdrawPendingRewardsEth and _withdrawPendingRewardsEigen
    function _withdrawPendingRewards(DelegatorStatus memory delegator, address token, uint32 index) internal {
        TokenPayment memory earnings;
        if (paymentsHistory[address(token)].length > 0) {
            earnings = paymentsHistory[address(token)][paymentsHistory[address(token)].length - 1];
        }
        
        // getting the payment details from the last claim of reward
        TokenPayment memory pastEarnings = paymentsHistory[address(token)][index];

        // check that delegator is only claiming rewards they deserve
        require(delegator.lastClaimedRewards <= pastEarnings.paymentTimestamp, "attempt to claim rewards too far in past");
        
        // compute the multiplying weight used for evaluating the reward for ETH stake
        uint256 earningsPerWeightDelta = earnings.earnedPerWeightAllTimeEth - pastEarnings.earnedPerWeightAllTimeEth;
        
        // calculate the pending reward for the delegator due to its delegation of ETH to the operator
        uint256 pending = (earningsPerWeightDelta * delegator.weightEth) / (totalWeightEth * REWARD_SCALING);
        
        // compute the multiplying weight used for evaluating the reward for Eigen stake
        earningsPerWeightDelta = earnings.earnedPerWeightAllTimeEigen - pastEarnings.earnedPerWeightAllTimeEigen;
        
        // calculate the pending reward for the delegator due to its delegation of Eigen to the operator
        pending += (earningsPerWeightDelta * delegator.weightEigen) / (totalWeightEigen * REWARD_SCALING);
        
        // transfer the pending rewards for token
        if (pending > 0) {
            IERC20(token).transfer(msg.sender, pending);
        }
    }

//TODO: move logic for 'weightOfEth' and 'weightOfEigen' to separate contract, in the event that we want to use it elsewhere
//      currently it heavily resembles the logic in the DataLayrVoteWeigher contract
    /**
     *  @notice returns the total ETH value of staked assets of the given staker in EigenLayr
     *          via this delegation term's operator.    
     */
    /**
     *  @dev for each investment strategy where the delegator has staked its asset,
     *       it needs to call that investment strategy's "underlyingEthValueOfShares" function
     *       to determine the value of delegator's shares in that investment strategy in ETH.        
     */ 
    function weightOfEth(address delegator) public returns(uint256) {
        // get the ETH that has been staked by a delegator in the settlement layer (beacon chain) 
        uint256 weight = (investmentManager.getConsensusLayerEth(delegator) * consensusLayerPercent) / 100;
        
        // get the strategies where delegator's assets has been staked
        IInvestmentStrategy[] memory investorStrats = investmentManager.getStrategies(delegator);

        // get the shares in the strategies where delegator's assets has been staked
        uint256[] memory investorShares = investmentManager.getStrategyShares(delegator);

        uint256 investorStratsLength = investorStrats.length;
        for (uint256 i; i < investorStratsLength;) {
            // get the underlying ETH value of the shares
            // each investment strategy have their own description of ETH value per share.
            weight += investorStrats[i].underlyingEthValueOfShares(investorShares[i]);
            unchecked {
                ++i;
            }
        }

        return weight;
    }
    /// @notice similar to 'weightOfEth' but restricted to not modifying state
    function weightOfEthView(address delegator) public view returns(uint256) {
        // get the ETH that has been staked by a delegator in the settlement layer (beacon chain) 
        uint256 weight = (investmentManager.getConsensusLayerEth(delegator) * consensusLayerPercent) / 100;
        
        // get the strategies where delegator's assets has been staked
        IInvestmentStrategy[] memory investorStrats = investmentManager.getStrategies(delegator);

        // get the shares in the strategies where delegator's assets has been staked
        uint256[] memory investorShares = investmentManager.getStrategyShares(delegator);

        uint256 investorStratsLength = investorStrats.length;
        for (uint256 i; i < investorStratsLength;) {
            // get the underlying ETH value of the shares
            // each investment strategy have their own description of ETH value per share.
            weight += investorStrats[i].underlyingEthValueOfSharesView(investorShares[i]);
            unchecked {
                ++i;
            }
        }

        return weight;
    }
    function weightOfEigen(address user) public view returns(uint256) {
        return investmentManager.getEigen(user);
    } 
}