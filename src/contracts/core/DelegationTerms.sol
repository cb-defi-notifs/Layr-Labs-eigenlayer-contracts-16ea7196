// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IDelegationTerms.sol";
import "../interfaces/IServiceFactory.sol";

// TODO: dealing with pending payments to the contract at time of deposit / delegation (or deciding this design is acceptable)
// TODO: dynamic splitting of earnings between EIGEN and ETH delegators rather than the crappy, static implemenation of 'EIGEN_HOLDER_BIPS'
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
abstract contract DelegationTerms is IDelegationTerms {
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
     *          delegator's 
     */
    /** 
    */ 
    struct TokenPayment {
        //cumulative earnings of the token, per delegated ETH, scaled up by REWARD_SCALING
        uint112 earnedPerWeightAllTimeEth;
        //cumulative earnings of the token, per delegated EIGEN, scaled up by REWARD_SCALING
        uint112 earnedPerWeightAllTimeEigen;        
        //UTC timestamp at which the payment was received
        uint32 paymentTimestamp;
    }

    //constants. scaling factor and max operator fee are somewhat arbitrary within sane values
    uint256 internal constant REWARD_SCALING = 2**64;
    uint16 internal constant MAX_BIPS = 10000;
    uint16 internal constant MAX_OPERATOR_FEE_BIPS = 500;
    //portion of earnings going to EIGEN delegators, *after* operator fees -- TODO: handle this better
    uint16 internal constant EIGEN_HOLDER_BIPS = 5000;
    //max number of payment tokens, for sanity's sake
    uint16 internal constant MAX_PAYMENT_TOKENS = 256;
    //portion of all earnings (in BIPS) retained by operator
    uint16 public operatorFeeBips = 200;
    //operator
    address public operator;
    //important contracts -- used for access control
    IServiceFactory immutable serviceFactory;
    address immutable eigenLayrDelegation;
    //sum of individual delegator weights
    uint128 public totalWeightEth;
    uint128 public totalWeightEigen;

    //mapping from token => list of payments to this contract
    mapping(address => TokenPayment[]) public paymentsHistory;
    //mapping from delegator => weights + last timestamp that they claimed rewards
    mapping(address => DelegatorStatus) public delegatorStatus;
    //earnings to be withdrawn by the operator
    mapping(address => uint256) public operatorPendingEarnings;
    //list of active payment methods
    address[] public paymentTokens;

    event OperatorFeeBipsSet(uint16 previousValue, uint16 newValue);

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
        address _eigenLayrDelegation
    ){
        investmentManager = _investmentManager;
        //initialize operator as msg.sender
        operator = msg.sender;
        paymentTokens = _paymentTokens;
        serviceFactory = _serviceFactory;
        eigenLayrDelegation = _eigenLayrDelegation;
    }

    function setOperatorFeeBips(uint16 bips) external onlyOperator {
        require(bips <= MAX_OPERATOR_FEE_BIPS, "setOperatorFeeBips: input too high");
        emit OperatorFeeBipsSet(operatorFeeBips, bips);
        operatorFeeBips = bips;
    }

    //NOTE: currently there is no way to remove payment tokens
    function addPaymentToken(address token) external onlyOperator {
        require(paymentTokens.length < MAX_PAYMENT_TOKENS, "too many payment tokens");
        paymentTokens.push(token);
    }

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
     * @dev Suppose 
     */ 
    /** 
     * @param token is the ERC20 token in which the middlewares are paying its rewards for the service,
     * @param amount is the amount of ERC20 tokens that is being paid as rewards. 
     */
    function payForService(IERC20 token, uint256 amount) external payable {
        // determine the query manager associated with the fee manager
        IQueryManager _queryManager = IFeeManager(msg.sender).queryManager();

        // only the fee manager can call this function
        require(msg.sender == address(_queryManager.feeManager()), "only feeManagers");

        // check if the query manager exists
        require(serviceFactory.queryManagerExists(_queryManager), "illegitimate queryManager");

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

        // 
        updatedEarnings.earnedPerWeightAllTimeEth += uint112(((amount * REWARD_SCALING) / totalWeightEth) * (MAX_BIPS - EIGEN_HOLDER_BIPS) / MAX_BIPS);
        updatedEarnings.earnedPerWeightAllTimeEigen += uint112(((amount * REWARD_SCALING) / totalWeightEigen) * (EIGEN_HOLDER_BIPS) / MAX_BIPS);
        updatedEarnings.paymentTimestamp = uint32(block.timestamp);
        paymentsHistory[address(token)].push(updatedEarnings);
    }

    function onDelegationReceived(address staker) external onlyDelegation {
        DelegatorStatus memory delegatorUpdate;
        delegatorUpdate.weightEth = uint112(weightOfEth(staker));
        delegatorUpdate.weightEigen = uint112(weightOfEigen(staker));
        delegatorUpdate.lastClaimedRewards = uint32(block.timestamp);
        totalWeightEth += delegatorUpdate.weightEth;
        totalWeightEigen += delegatorUpdate.weightEigen;
    }

//NOTE: currently this causes the delegator to lose any pending rewards
    function onDelegationWithdrawn(address staker) external onlyDelegation {
        DelegatorStatus memory delegator = delegatorStatus[staker];
        totalWeightEth -= delegator.weightEth;
        totalWeightEigen -= delegator.weightEigen;
        delegator.weightEth = 0;
        delegator.weightEigen = 0;
        //update storage at end
        delegatorStatus[staker];
    }

    //withdraw pending rewards for all tokens. indices are the locations in paymentsHistory to claim from
    function withdrawPendingRewards(uint32[] calldata indices) external {
        uint256 length = paymentTokens.length;
        require(indices.length == length, "incorrect input length");
        DelegatorStatus memory delegator = delegatorStatus[msg.sender];
        for (uint256 i; i < length;) {
            _withdrawPendingRewards(delegator, paymentTokens[i], indices[i]);
            unchecked {
                ++i;
            }
        }
        _updateDelegatorWeights(msg.sender);
    }

    //withdraw pending rewards for specified tokens. NOTE: pending rewards are LOST for other tokens!
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

//NOTE: must withdraw pending rewards first, or else they will be lost!
    function _updateDelegatorWeights(address user) internal {
        DelegatorStatus memory delegator = delegatorStatus[user];
        //update ETH weight
        uint256 newWeight = weightOfEth(user);
        uint256 previousWeight = delegator.weightEth;
        //if weight has increased
        if (newWeight > previousWeight) {
            totalWeightEth += uint128(newWeight - previousWeight);
        //if weight has decreased
        } else if (newWeight < previousWeight) {
            totalWeightEth -= uint128(previousWeight - previousWeight);
        }
        delegator.weightEth = uint112(newWeight);

        //update Eigen weight
        newWeight = weightOfEigen(user);
        previousWeight = delegator.weightEigen;
        if (newWeight > previousWeight) {
            totalWeightEigen += uint128(newWeight - previousWeight);
        //if weight has decreased
        } else if (newWeight < previousWeight) {
            totalWeightEigen -= uint128(previousWeight - previousWeight);
        }
        delegator.weightEigen = uint112(newWeight);

        //update latest timestamp claimed
        if (block.timestamp > delegator.lastClaimedRewards) {
            delegator.lastClaimedRewards = uint32(block.timestamp);
        }

        //update storage
        delegatorStatus[user] = delegator;
    }

    //withdraw pending rewards for a single token. **must update delegator's 'lastClaimedRewards' timestamp after invoking this**
    //combines _withdrawPendingRewardsEth and _withdrawPendingRewardsEigen
    function _withdrawPendingRewards(DelegatorStatus memory delegator, address token, uint32 index) internal {
        TokenPayment memory earnings;
        if (paymentsHistory[address(token)].length > 0) {
            earnings = paymentsHistory[address(token)][paymentsHistory[address(token)].length - 1];
        }
        TokenPayment memory pastEarnings = paymentsHistory[address(token)][index];
        //check that delegator is only claiming rewards they deserve
        require(delegator.lastClaimedRewards <= pastEarnings.paymentTimestamp, "attempt to claim rewards too far in past");
        uint256 earningsPerWeightDelta = earnings.earnedPerWeightAllTimeEth - pastEarnings.earnedPerWeightAllTimeEth;
        uint256 pending = (earningsPerWeightDelta * delegator.weightEth) / (totalWeightEth * REWARD_SCALING);
        earningsPerWeightDelta = earnings.earnedPerWeightAllTimeEigen - pastEarnings.earnedPerWeightAllTimeEigen;
        pending += (earningsPerWeightDelta * delegator.weightEigen) / (totalWeightEigen * REWARD_SCALING);
            if (pending > 0) {
            IERC20(token).transfer(msg.sender, pending);
        }
    }

    //TODO: move code copied from DataLayrVoteWeigher to its own file?
    //BEGIN COPIED CODE
    IInvestmentManager public investmentManager;
    //consensus layer ETH counts for 'consensusLayerPercent'/100 when compared to ETH deposited in the system itself
    uint256 public consensusLayerPercent = 10;



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

        for (uint256 i = 0; i < investorStrats.length; i++) {
            // get the underlying ETH value of the shares
            // each investment strategy have their own description of ETH value per share.
            weight += investorStrats[i].underlyingEthValueOfShares(investorShares[i]);
        }
        return weight;
    }
    //END COPIED CODE
    function weightOfEigen(address user) public view returns(uint256) {
        return investmentManager.getEigen(user);
    } 
}