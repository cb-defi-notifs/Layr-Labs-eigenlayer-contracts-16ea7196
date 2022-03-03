// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./InvestmentManager.sol";

contract Slasher {
    address public governor;
    InvestmentManager public investmentManager;
    mapping(address => bool) canSlash;

    constructor(InvestmentManager _investmentManager) {
        governor = msg.sender;
        investmentManager = _investmentManager;
    }

    function addPermissionedContracts(address[] calldata contracts) external {
        require(msg.sender == governor, "Only governor");
        for (uint256 i = 0; i < contracts.length; i++) {
            canSlash[contracts[i]] = true;
        } 
    }

    function removePermissionedContracts(address[] calldata contracts) external {
        require(msg.sender == governor, "Only governor");
        for (uint256 i = 0; i < contracts.length; i++) {
            canSlash[contracts[i]] = false;
        } 
    }

    function slashShares(
        address slashed,
        address recipient,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata strategyIndexes,
        uint256[] calldata amounts,
        uint256 maxSlashedAmount
    ) external {
        require(canSlash[msg.sender], "Only permissioned contracts can slash");
        investmentManager.slashShares(slashed, recipient, strategies, strategyIndexes, amounts, maxSlashedAmount);
    }
}
