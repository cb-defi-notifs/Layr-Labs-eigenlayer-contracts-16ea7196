// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/InvestmentInterfaces.sol";
import "../interfaces/CoreInterfaces.sol";
import "../interfaces/MiddlewareInterfaces.sol";
import "./BLS.sol";

// TODO: weight updating, *dealing with pending payments to the contract at time of deposit / delegation*
abstract contract DelegationTerms is IDelegationTerms {
    struct DelegatorStatus {
        //delegator weight
        uint128 weight;
        //ensures delegates do not receive undue rewards
        int128 claimedRewards;
    }

    //constant scaling factor
    uint256 internal constant REWARD_SCALING = 2**64;
    uint16 internal constant MAX_BIPS = 10000;
    uint16 internal constant MAX_OPERATOR_FEE_BIPS = 1000;
    //portion of all earnings (in BIPS) retained by operator
    uint16 public operatorFeeBips = 200;
    //operator
    address public operator;
    //earnings to be withdrawn by the operator
    uint256 public operatorPendingEarnings;
    //sum of individual delegator weights
    uint256 public totalWeight;
    //sum of earnings of this contract, over all time, per unit weight at the time of earning
    uint256 public earnedPerWeightAllTime;
    //delegate => weight
    mapping(address => DelegatorStatus) public delegatorInfo;

    event OperatorFeeBipsSet(uint16 previousValue, uint16 newValue);

    function setOperatorFeeBips(uint16 bips) external {
        require(bips <= MAX_OPERATOR_FEE_BIPS, "setOperatorFeeBips: input too high");
        require(msg.sender == operator, "onlyOperator");
        emit OperatorFeeBipsSet(operatorFeeBips, bips);
        operatorFeeBips = bips;
    }

    function operatorWithdrawal() external {
        uint256 pending = operatorPendingEarnings;
        operatorPendingEarnings = 0;
        if (pending > 0) {
            // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
            (bool success, ) = payable(operator).call{ value: uint256(int256(pending)) }("");
            require(success, "DelegationTerms: failed to send value");
        }
    }

    function payForService(IQueryManager queryManager, IERC20[] calldata tokens, uint256[] calldata amounts) external payable {
        uint256 ethSent = msg.value;
        if (operatorFeeBips > 0) {
            uint256 operatorEarnings = (ethSent * operatorFeeBips) / MAX_BIPS;
            operatorPendingEarnings += operatorEarnings;
            ethSent -= operatorPendingEarnings;
        }
        earnedPerWeightAllTime += (ethSent * REWARD_SCALING) / totalWeight;
    }

    function onDelegationReceived(address staker, IInvestmentStrategy[] calldata strategies, uint256[] calldata shares) external {
        DelegatorStatus storage delegator = delegatorInfo[staker];
        uint256 weight = weightOf(staker);
        delegator.claimedRewards += int128(uint128((earnedPerWeightAllTime * weight) / (totalWeight * REWARD_SCALING)));
        delegator.weight += uint128(weight);
        totalWeight += weight;
    }

    function onDelegationWithdrawn(address staker, IInvestmentStrategy[] calldata strategies, uint256[] calldata shares) external {
        DelegatorStatus storage delegator = delegatorInfo[staker];
        delegator.claimedRewards -= int128(uint128((earnedPerWeightAllTime * delegator.weight) / (totalWeight * REWARD_SCALING)));
        totalWeight -= delegator.weight;
        delegator.weight = 0;
    }

    function withdrawPendingRewards() external {  
        _withdrawPendingRewards(msg.sender);
        _updateDelegatorWeight(msg.sender);   
    }

    function updateDelegatorWeight(address staker) external {
        _updateDelegatorWeight(staker);
    }

    function _updateDelegatorWeight(address staker) internal {
        DelegatorStatus storage delegator = delegatorInfo[staker];
        uint256 newWeight = weightOf(staker);
        uint256 previousWeight = delegator.weight;
        //if weight has increased
        if (newWeight > previousWeight) {
            totalWeight += (newWeight - previousWeight);
            delegator.weight = uint128(newWeight);
            delegator.claimedRewards += int128(uint128((earnedPerWeightAllTime * (newWeight - previousWeight)) / (totalWeight * REWARD_SCALING)));
        //if weight has decreased
        } else if (newWeight < previousWeight) {
            totalWeight -= (previousWeight - previousWeight);
            delegator.weight = uint128(newWeight);
            delegator.claimedRewards -= int128(uint128((earnedPerWeightAllTime * (previousWeight - newWeight)) / (totalWeight * REWARD_SCALING)));
        }
    }

    function _withdrawPendingRewards(address user) internal {
        DelegatorStatus storage delegator = delegatorInfo[user];
        int128 proceedsAllTime = int128(uint128( (earnedPerWeightAllTime * delegator.weight) / (totalWeight * REWARD_SCALING) ));
        int128 pending = proceedsAllTime - delegator.claimedRewards;
        delegator.claimedRewards = proceedsAllTime;
        if (pending > 0) {
            // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
            (bool success, ) = payable(user).call{ value: uint256(int256(pending)) }("");
            require(success, "DelegationTerms: failed to send value");
        }
    }

    //TODO: move code copied from DataLayrVoteWeigher to its own file
    //BEGIN COPIED CODE
    IInvestmentManager public investmentManager;
    //consensus layer ETH counts for 'consensusLayerPercent'/100 when compared to ETH deposited in the system itself
    uint256 public consensusLayerPercent = 10;
    
    constructor(IInvestmentManager _investmentManager){
        investmentManager = _investmentManager;
        //initialize operator as msg.sender
        operator = msg.sender;
    }

    function weightOf(address user) public returns(uint256) {
        uint256 weight = (investmentManager.getConsensusLayerEth(user) * consensusLayerPercent) / 100;
        IInvestmentStrategy[] memory investorStrats = investmentManager.getStrategies(user);
        uint256[] memory investorShares = investmentManager.getStrategyShares(user);
        for (uint256 i = 0; i < investorStrats.length; i++) {
            weight += investorStrats[i].underlyingEthValueOfShares(investorShares[i]);
        }
        return weight;
    }
    //END COPIED CODE
}