// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/MiddlewareInterfaces.sol";
import "../interfaces/CoreInterfaces.sol";
import "./QueryManager.sol";


contract DataLayrVoteWeigher is IVoteWeighter {
    IInvestmentManager public investmentManager;
    
    constructor(IInvestmentManager _investmentManager){
        investmentManager = _investmentManager;
    }


    function weightOfOperator(address) external pure returns(uint256) {
        return 0;
    }
    
}