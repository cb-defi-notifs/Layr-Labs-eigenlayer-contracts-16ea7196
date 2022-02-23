// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/InvestmentInterfaces.sol";
import "../interfaces/CoreInterfaces.sol";
import "../interfaces/MiddlewareInterfaces.sol";
import "./BLS.sol";

// TODO: weight updating, *dealing with pending payments to the operator at time of deposit*
//TODO: dealing with ownership + operator cut
abstract contract DelegationTerms is IDelegationTerms {
    struct delegatorStatus {
        //delegator weight
        uint128 weight;
        //ensures delegates do not receive undue rewards
        int128 claimedRewards;
    }

    //constant scaling factor
    uint256 internal constant REWARD_SCALING = 2**64;
    //sum of individual delegator weights
    uint256 public totalWeight;
    //sum of earnings of this contract, over all time, per unit weight at the time of earning
    uint256 public earnedPerWeightAllTime;
    //delegate => weight
    mapping(address => delegatorStatus) public delegatorInfo;

    function payForService(IQueryManager queryManager, IERC20[] calldata tokens, uint256[] calldata amounts) external payable {
        uint256 ethSent = msg.value;
        earnedPerWeightAllTime += (ethSent * REWARD_SCALING) / totalWeight;
    }

    function onDelegationReceived(address staker, IInvestmentStrategy[] calldata strategies, uint256[] calldata shares) external {
        delegatorStatus storage delegator = delegatorInfo[staker];
        uint256 weight = weightOf(staker);
        delegator.claimedRewards += int128(uint128((earnedPerWeightAllTime * weight) / (totalWeight * REWARD_SCALING)));
        delegator.weight += uint128(weight);
        totalWeight += weight;
    }

    function onDelegationWithdrawn(address staker, IInvestmentStrategy[] calldata strategies, uint256[] calldata shares) external {
        delegatorStatus storage delegator = delegatorInfo[staker];
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
        delegatorStatus storage delegator = delegatorInfo[staker];
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
        delegatorStatus storage delegator = delegatorInfo[user];
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