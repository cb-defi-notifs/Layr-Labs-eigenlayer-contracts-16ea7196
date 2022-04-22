// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./InvestmentManager.sol";
import "../utils/Governed.sol";
import "../interfaces/IServiceFactory.sol";

/**
 * @notice This contract specifies details on slashing. The functionalities are:
 *          - adding contracts who have permission to perform slashing,
 *          - revoking permission for slashing from specified contracts,
 *          - calling investManager to do actual slashing.          
 */
contract Slasher is Governed {
    InvestmentManager public investmentManager;
    mapping(address => bool) public globallyPermissionedContracts;
    mapping(address => bool) public serviceFactories;
    // user => contract => if that contract can slash the user
    mapping(address => mapping(address => bool)) public optedIntoSlashing;

    constructor(InvestmentManager _investmentManager, address _eigenLayrGovernance) {
        _transferGovernor(_eigenLayrGovernance);
        investmentManager = _investmentManager;
    }

    /**
     * @notice used for giving permission of slashing to contracts. 
     */
    function addPermissionedContracts(address[] calldata contracts) external onlyGovernor {
        for (uint256 i = 0; i < contracts.length;) {
            globallyPermissionedContracts[contracts[i]] = true;
            unchecked {
                ++i;
            }
        } 
    }

    /**
     * @notice used for revoking permission of slashing from contracts. 
     */
    function removePermissionedContracts(address[] calldata contracts) external onlyGovernor {
        for (uint256 i = 0; i < contracts.length;) {
            globallyPermissionedContracts[contracts[i]] = false;
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice used for marking approved service factories 
     */
    function addserviceFactories(address[] calldata contracts) external onlyGovernor {
        for (uint256 i = 0; i < contracts.length;) {
            serviceFactories[contracts[i]] = true;
            unchecked {
                ++i;
            }
        } 
    }

    /**
     * @notice used for revoking approval of service factories
     */
    function removeserviceFactories(address[] calldata contracts) external onlyGovernor {
        for (uint256 i = 0; i < contracts.length;) {
            serviceFactories[contracts[i]] = false;
            unchecked {
                ++i;
            }
        }
    }

    // give the contract permission to slash your funds
    function allowToSlash(address slashingContract) external {
        optedIntoSlashing[msg.sender][slashingContract] = true;
    }

    function canSlash(address toBeSlashed, address slashingContract) public view returns (bool) {
        if (optedIntoSlashing[toBeSlashed][slashingContract]) {
            return true;
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
        require(globallyPermissionedContracts[msg.sender], "Only permissioned contracts can slash");
        investmentManager.slashShares(slashed, recipient, strategies, strategyIndexes, amounts, maxSlashedAmount);
    }
}
