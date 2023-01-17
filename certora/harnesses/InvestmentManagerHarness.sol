// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../munged/core/InvestmentManager.sol";

contract InvestmentManagerHarness is InvestmentManager {
    constructor(IEigenLayerDelegation _delegation, IEigenPodManager _eigenPodManager, ISlasher _slasher)
        InvestmentManager(_delegation, _eigenPodManager, _slasher)
        {}

    function strategy_is_in_stakers_array(address staker, IInvestmentStrategy strategy) public view returns (bool) {
        uint256 length = investorStrats[staker].length;
        for (uint256 i = 0; i < length; ++i) {
            if (investorStrats[staker][i] == strategy) {
                return true;
            }
        }
        return false;
    }

    function num_times_strategy_is_in_stakers_array(address staker, IInvestmentStrategy strategy) public view returns (uint256) {
        uint256 length = investorStrats[staker].length;
        uint256 res = 0;
        for (uint256 i = 0; i < length; ++i) {
            if (investorStrats[staker][i] == strategy) {
                res += 1;
            }
        }
        return res;
    }

    // checks that investorStrats[staker] contains no duplicates and that all strategies in array have nonzero shares
    function array_exhibits_properties(address staker) public view returns (bool) {
        uint256 length = investorStrats[staker].length;
        uint256 res = 0;
        // loop for each strategy in array
        for (uint256 i = 0; i < length; ++i) {
            IInvestmentStrategy strategy = investorStrats[staker][i];
            // check that staker's shares in strategy are nonzero
            if (investorStratShares[staker][strategy] == 0) {
                return false;
            }
            // check that strategy is not duplicated in array
            if (num_times_strategy_is_in_stakers_array(staker, strategy) != 1) {
                return false;
            }
        }
        return true;
    }
}