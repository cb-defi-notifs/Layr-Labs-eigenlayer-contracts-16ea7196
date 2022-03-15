// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IDelegationTerms.sol";
import "../interfaces/IServiceFactory.sol";

// TODO: weight updating, *dealing with pending payments to the contract at time of deposit / delegation*
// TODO: more info on split between EIGEN holder and ETH holders
// TODO: make 'payForService' make sense.
// TODO: add ability to manage (especially add!) payment tokens
abstract contract DelegationTerms is IDelegationTerms {
    //defines statuses for payment tokens
    enum Status {
        //token has never been added as a payment method
        NeverAdded,
        //token is an active payment method
        Active,
        //token was previously added as a payment method but is now inactive
        Inactive
    }
    struct TokenStatus {
        IERC20 token;
        uint8 status;
    }
    //stored for each delegator to this contract
    struct DelegatorStatus {
        //delegator weights
        uint112 weightEth;
        uint112 weightEigen;
        //ensures delegators do not receive undue rewards
        uint32 lastClaimedRewards;
    }
    struct TokenPayment {
        uint112 earnedPerWeightAllTimeEth;
        uint112 earnedPerWeightAllTimeEigen;        
        uint32 paymentTimestamp;
    }

    //constant scaling factors
    uint256 internal constant REWARD_SCALING = 2**64;
    uint16 internal constant MAX_BIPS = 10000;
    uint16 internal constant MAX_OPERATOR_FEE_BIPS = 1000;
    //portion of earnings going to EIGEN delegators, *after* operator fees -- TODO: handle this better
    uint16 internal constant EIGEN_HOLDER_BIPS = 5000;
    //portion of all earnings (in BIPS) retained by operator
    uint16 public operatorFeeBips = 200;
    //operator
    address public operator;
    IServiceFactory immutable serviceFactory;
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

    constructor(IInvestmentManager _investmentManager, address[] memory _paymentTokens, IServiceFactory _serviceFactory){
        investmentManager = _investmentManager;
        //initialize operator as msg.sender
        operator = msg.sender;
        paymentTokens = _paymentTokens;
        serviceFactory = _serviceFactory;
    }

    function setOperatorFeeBips(uint16 bips) external onlyOperator {
        require(bips <= MAX_OPERATOR_FEE_BIPS, "setOperatorFeeBips: input too high");
        emit OperatorFeeBipsSet(operatorFeeBips, bips);
        operatorFeeBips = bips;
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

//TODO: change this function's signature?
    function payForService(IQueryManager queryManager, IERC20 token, uint256 amount) external payable {
        IQueryManager _queryManager = IFeeManager(msg.sender).queryManager();
        require(msg.sender == address(_queryManager.feeManager()), "only feeManagers");
        require(serviceFactory.queryManagerExists(_queryManager), "illegitimate queryManager");
        TokenPayment memory updatedEarnings;
        if (paymentsHistory[address(token)].length > 0) {
            updatedEarnings = paymentsHistory[address(token)][paymentsHistory[address(token)].length - 1];
        }
        if (operatorFeeBips > 0) {
            uint256 operatorEarnings = (amount * operatorFeeBips) / MAX_BIPS;
            operatorPendingEarnings[address(token)] += operatorEarnings;
            amount -= operatorEarnings;
        }
        updatedEarnings.earnedPerWeightAllTimeEth += uint112(((amount * REWARD_SCALING) / totalWeightEth) * (MAX_BIPS - EIGEN_HOLDER_BIPS) / MAX_BIPS);
        updatedEarnings.earnedPerWeightAllTimeEigen += uint112(((amount * REWARD_SCALING) / totalWeightEigen) * (EIGEN_HOLDER_BIPS) / MAX_BIPS);
        updatedEarnings.paymentTimestamp = uint32(block.timestamp);
        paymentsHistory[address(token)].push(updatedEarnings);
    }

//TODO: ACCESS CONTROL
    function onDelegationReceived(address staker) external {
        DelegatorStatus memory delegatorUpdate;
        delegatorUpdate.weightEth = uint112(weightOfEth(staker));
        delegatorUpdate.weightEigen = uint112(weightOfEigen(staker));
        delegatorUpdate.lastClaimedRewards = uint32(block.timestamp);
        totalWeightEth += delegatorUpdate.weightEth;
        totalWeightEigen += delegatorUpdate.weightEigen;
    }

//TODO: ACCESS CONTROL
//TODO: forward additional data in this call? right now loop is commented out so contract cannot be bricked by adding tons of paymentTokens
//NOTE: currently this causes the delegator to lose any pending rewards
    function onDelegationWithdrawn(address staker) external {
        // uint256 length = paymentTokens.length;
        // for (uint256 i; i < length;) {
        //     _withdrawPendingRewardsEth(paymentTokens[i]);
        //     _withdrawPendingRewardsEigen(paymentTokens[i]);
        //     unchecked {
        //         ++i;
        //     }
        // }
        //TODO: can this be better optimized?
        DelegatorStatus storage delegator = delegatorStatus[staker];
        totalWeightEth -= delegator.weightEth;
        totalWeightEigen -= delegator.weightEigen;
        delegator.weightEth = 0;
        delegator.weightEigen = 0;
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

/*
    function _withdrawPendingRewardsEth(address token, uint32 index) internal {
        DelegatorStatus storage delegator = delegatorStatus[msg.sender];
        TokenPayment memory earnings;
        if (paymentsHistory[address(token)].length > 0) {
            earnings = paymentsHistory[address(token)][paymentsHistory[address(token)].length - 1];
        }
        TokenPayment memory pastEarnings = paymentsHistory[address(token)][index];
        //check that delegator is only claiming rewards they deserve
        require(delegator.lastClaimedRewards <= pastEarnings.paymentTimestamp, "attempt to claim rewards too far in past");
        uint256 earningsPerWeightDelta = earnings.earnedPerWeightAllTimeEth - pastEarnings.earnedPerWeightAllTimeEth;
        uint256 pending = (earningsPerWeightDelta * delegator.weightEth) / (totalWeightEth * REWARD_SCALING);
        if (pending > 0) {
            token.transfer(msg.sender, pending);
        }
    }

    function _withdrawPendingRewardsEigen(address token, uint32 index) internal {
        DelegatorStatus storage delegator = delegatorStatus[msg.sender];
        TokenPayment memory earnings;
        if (paymentsHistory[address(token)].length > 0) {
            earnings = paymentsHistory[address(token)][paymentsHistory[address(token)].length - 1];
        }
        TokenPayment memory pastEarnings = paymentsHistory[address(token)][index];
        //check that delegator is only claiming rewards they deserve
        require(delegator.lastClaimedRewards <= pastEarnings.paymentTimestamp, "attempt to claim rewards too far in past");
        uint256 earningsPerWeightDelta = earnings.earnedPerWeightAllTimeEigen - pastEarnings.earnedPerWeightAllTimeEigen;
        uint256 pending = (earningsPerWeightDelta * delegator.weightEth) / (totalWeightEth * REWARD_SCALING);
        if (pending > 0) {
            token.transfer(msg.sender, pending);
        }
    }
*/

    //TODO: move code copied from DataLayrVoteWeigher to its own file
    //BEGIN COPIED CODE
    IInvestmentManager public investmentManager;
    //consensus layer ETH counts for 'consensusLayerPercent'/100 when compared to ETH deposited in the system itself
    uint256 public consensusLayerPercent = 10;

    function weightOfEth(address user) public returns(uint256) {
        uint256 weight = (investmentManager.getConsensusLayerEth(user) * consensusLayerPercent) / 100;
        IInvestmentStrategy[] memory investorStrats = investmentManager.getStrategies(user);
        uint256[] memory investorShares = investmentManager.getStrategyShares(user);
        for (uint256 i = 0; i < investorStrats.length; i++) {
            weight += investorStrats[i].underlyingEthValueOfShares(investorShares[i]);
        }
        return weight;
    }
    //END COPIED CODE

    function weightOfEigen(address user) public view returns(uint256) {
        return investmentManager.getEigen(user);
    } 
}