// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.11;

import "../interfaces/IOperatorPermitter.sol";

contract MockOperatorPermitter is IOperatorPermitter {
    function operatorPermitted(address operator) external returns (bool) {
        if (operator != address(0)) {
            return true;
        } else {
            return false;
        }
    }
}