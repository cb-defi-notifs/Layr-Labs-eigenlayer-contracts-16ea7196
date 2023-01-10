// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../munged/core/Slasher.sol";

contract SlasherHarness is Slasher {

    constructor(IInvestmentManager _investmentManager, IEigenLayrDelegation _delegation) Slasher(_investmentManager, _delegation) {}
    
    /// Harnessed functions
    function get_is_operator(address staker) external returns (bool) {
        return delegation.isOperator(staker);        
    }

    function get_is_delegated(address staker) external returns (bool) {
        return delegation.isDelegated(staker);        
    }
}