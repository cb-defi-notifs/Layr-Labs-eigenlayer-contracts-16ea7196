// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IDelegationTerms.sol";

// TODO: weight updating, *dealing with pending payments to the contract at time of deposit / delegation*
// TODO: more info on split between NFGT holder and ETH holders
// TODO: make 'payForService' make sense.
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
    //portion of earnings going to NFGT delegators, *after* operator fees -- TODO: handle this better
    uint16 internal constant NFGT_HOLDER_BIPS = 5000;
    //portion of all earnings (in BIPS) retained by operator
    uint16 public operatorFeeBips = 200;
    //operator
    address public operator;
    //earnings to be withdrawn by the operator
    uint256 public operatorPendingEarnings;
    //sum of individual delegator weights
    uint256 public totalWeightEth;
    uint256 public totalWeightNfgt;
    //sum of earnings of this contract, over all time, per unit weight at the time of earning
    uint256 public earnedPerWeightAllTimeEth;
    uint256 public earnedPerWeightAllTimeNfgt;
    //token used for payment
    IERC20 public immutable PAYMENT_TOKEN;
    //delegate => weight
    mapping(address => DelegatorStatus) public ethDelegatorInfo;
    mapping(address => DelegatorStatus) public nfgtDelegatorInfo;

    event OperatorFeeBipsSet(uint16 previousValue, uint16 newValue);

    constructor(IInvestmentManager _investmentManager, IERC20 _PAYMENT_TOKEN){
        investmentManager = _investmentManager;
        //initialize operator as msg.sender
        operator = msg.sender;
        PAYMENT_TOKEN = _PAYMENT_TOKEN;
    }

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
        uint256 ethSent;
        if (operatorFeeBips > 0) {
            uint256 operatorEarnings = (ethSent * operatorFeeBips) / MAX_BIPS;
            operatorPendingEarnings += operatorEarnings;
            ethSent -= operatorPendingEarnings;
        }
        earnedPerWeightAllTimeEth += ((ethSent * REWARD_SCALING) / totalWeightEth) * (MAX_BIPS - NFGT_HOLDER_BIPS) / MAX_BIPS;
        earnedPerWeightAllTimeNfgt += ((ethSent * REWARD_SCALING) / totalWeightNfgt) * (NFGT_HOLDER_BIPS) / MAX_BIPS;
    }

    function onDelegationReceived(address staker, IInvestmentStrategy[] calldata strategies, uint256[] calldata shares) external {
        DelegatorStatus storage delegator = ethDelegatorInfo[staker];
        uint256 weight = weightOf(staker);
        delegator.claimedRewards += int128(uint128((earnedPerWeightAllTimeEth * weight) / (totalWeightEth * REWARD_SCALING)));
        delegator.weight += uint128(weight);
        totalWeightEth += weight;
    }

    function onDelegationWithdrawn(address staker, IInvestmentStrategy[] calldata strategies, uint256[] calldata shares) external {
        DelegatorStatus storage delegator = ethDelegatorInfo[staker];
        delegator.claimedRewards -= int128(uint128((earnedPerWeightAllTimeEth * delegator.weight) / (totalWeightEth * REWARD_SCALING)));
        totalWeightEth -= delegator.weight;
        delegator.weight = 0;
    }

    function withdrawPendingRewards() external {  
        _withdrawPendingRewardsEth(msg.sender);
        _withdrawPendingRewardsNfgt(msg.sender);
        _updateDelegatorWeightEth(msg.sender);
        _updateDelegatorWeightNfgt(msg.sender); 
    }

    function updateDelegatorWeight(address user) external {
        _updateDelegatorWeightEth(user);
        _updateDelegatorWeightNfgt(user);
    }

    function _updateDelegatorWeightEth(address user) internal {
        DelegatorStatus storage delegator = ethDelegatorInfo[user];
        uint256 newWeight = weightOf(user);
        uint256 previousWeight = delegator.weight;
        //if weight has increased
        if (newWeight > previousWeight) {
            totalWeightEth += (newWeight - previousWeight);
            delegator.weight = uint128(newWeight);
            delegator.claimedRewards += int128(uint128((earnedPerWeightAllTimeEth * (newWeight - previousWeight)) / (totalWeightEth * REWARD_SCALING)));
        //if weight has decreased
        } else if (newWeight < previousWeight) {
            totalWeightEth -= (previousWeight - previousWeight);
            delegator.weight = uint128(newWeight);
            delegator.claimedRewards -= int128(uint128((earnedPerWeightAllTimeEth * (previousWeight - newWeight)) / (totalWeightEth * REWARD_SCALING)));
        }
    }

    function _updateDelegatorWeightNfgt(address user) internal {
        DelegatorStatus storage delegator = nfgtDelegatorInfo[user];
        uint256 newWeight = nfgtWeightOf(user);
        uint256 previousWeight = delegator.weight;
        //if weight has increased
        if (newWeight > previousWeight) {
            totalWeightEth += (newWeight - previousWeight);
            delegator.weight = uint128(newWeight);
            delegator.claimedRewards += int128(uint128((earnedPerWeightAllTimeNfgt * (newWeight - previousWeight)) / (totalWeightEth * REWARD_SCALING)));
        //if weight has decreased
        } else if (newWeight < previousWeight) {
            totalWeightEth -= (previousWeight - previousWeight);
            delegator.weight = uint128(newWeight);
            delegator.claimedRewards -= int128(uint128((earnedPerWeightAllTimeNfgt * (previousWeight - newWeight)) / (totalWeightEth * REWARD_SCALING)));
        }
    }

    function _withdrawPendingRewardsEth(address user) internal {
        DelegatorStatus storage delegator = ethDelegatorInfo[user];
        int128 proceedsAllTime = int128(uint128( (earnedPerWeightAllTimeEth * delegator.weight) / (totalWeightEth * REWARD_SCALING) ));
        int128 pending = proceedsAllTime - delegator.claimedRewards;
        delegator.claimedRewards = proceedsAllTime;
        if (pending > 0) {
            // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
            (bool success, ) = payable(user).call{ value: uint256(int256(pending)) }("");
            require(success, "DelegationTerms: failed to send value");
        }
    }

    function _withdrawPendingRewardsNfgt(address user) internal {
        DelegatorStatus storage delegator = nfgtDelegatorInfo[user];
        int128 proceedsAllTime = int128(uint128( (earnedPerWeightAllTimeNfgt * delegator.weight) / (totalWeightEth * REWARD_SCALING) ));
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

    function nfgtWeightOf(address user) public view returns(uint256) {
        return investmentManager.getNfgtStaked(user);
    } 
}