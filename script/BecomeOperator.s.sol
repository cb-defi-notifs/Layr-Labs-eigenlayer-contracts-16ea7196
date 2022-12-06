// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./EigenLayerParser.sol";

contract BecomeOperator is Script, DSTest, EigenLayerParser {
    //performs basic deployment before each test
    function run() external {
        parseEigenLayerParams();
        vm.broadcast(msg.sender);
        delegation.registerAsOperator(IDelegationTerms(msg.sender));
    }
}
