// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/InvestmentInterfaces.sol";
import "../interfaces/CoreInterfaces.sol";
import "../interfaces/MiddlewareInterfaces.sol";
import "./BLS.sol";


// TODO: Best way to divide up shares?
contract DelegationTerms is IDelegationTerms {
    mapping(IInvestmentStrategy => uint256) public cummulativeRewardsPerStrategyShare;
    mapping(address => mapping(IInvestmentStrategy => uint256)) public stakerToStrategyToLastRewardsPerStrategyShare;

    function onDelegationReceived(address staker, IInvestmentStrategy[] calldata strategies, uint256[] calldata shares) external {
        // stakerToLastRewardsPerStake[staker] = cummulativeRewardsPerEthStaked;
    }

    function onDelegationWithdrawn(address staker, IInvestmentStrategy[] calldata strategies, uint256[] calldata shares) external {

    }

    function withdrawPendingRewards() external {

    }
}