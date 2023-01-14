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
}