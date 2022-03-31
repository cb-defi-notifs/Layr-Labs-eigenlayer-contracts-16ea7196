// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./InvestmentManager.sol";

/**
 * @notice This contract specifies details on slashing. The functionalities are:
 *          - adding contracts who have permission to perform slashing,
 *          - revoking permission for slashing from specified contracts,
 *          - calling investManager to do actual slashing.          
 */
contract Slasher {
    address public governor;
    InvestmentManager public investmentManager;
    mapping(address => bool) canSlash;

    constructor(InvestmentManager _investmentManager) {
        governor = msg.sender;
        investmentManager = _investmentManager;
    }

    /**
     * @notice used for giving permission of slashing to contracts. 
     */
    function addPermissionedContracts(address[] calldata contracts) external {
        require(msg.sender == governor, "Only governor");
        for (uint256 i = 0; i < contracts.length; i++) {
            canSlash[contracts[i]] = true;
        } 
    }

    /**
     * @notice used for revoking permission of slashing from contracts. 
     */
    function removePermissionedContracts(address[] calldata contracts) external {
        require(msg.sender == governor, "Only governor");
        for (uint256 i = 0; i < contracts.length; i++) {
            canSlash[contracts[i]] = false;
        } 
    }


    /**
     * @notice used for calling slashing function in investmentManager contract.
     */
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
