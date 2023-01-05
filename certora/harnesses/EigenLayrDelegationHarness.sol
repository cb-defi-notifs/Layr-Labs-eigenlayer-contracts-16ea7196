// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../munged/core/EigenLayrDelegation.sol";

contract EigenLayrDelegationHarness is EigenLayrDelegation {

    constructor(IInvestmentManager _investmentManager, ISlasher _slasher) EigenLayrDelegation(_investmentManager, _slasher) {}


    /// Harnessed functions
    function decreaseDelegatedShares(
        address staker,
        IInvestmentStrategy strategy1,
        IInvestmentStrategy strategy2,
        uint256 share1,
        uint256 share2
        ) external {
            IInvestmentStrategy[] memory strategies = new IInvestmentStrategy[](2);
            uint256[] memory shares = new uint256[](2);
            strategies[0] = strategy1;
            strategies[1] = strategy2;
            shares[0] = share1;
            shares[1] = share2;
            super.decreaseDelegatedShares(staker,strategies,shares);
    }

    function get_operatorShares(address operator, IInvestmentStrategy strategy) public view returns(uint256) {
        return operatorShares[operator][strategy];
    }
}