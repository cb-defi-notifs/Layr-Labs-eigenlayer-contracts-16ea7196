// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IERC20.sol";
import "../Eigen.sol";
import "../../interfaces/IDepositContract.sol";
import "../../interfaces/IInvestmentManager.sol";
import "../../middleware/QueryManager.sol";

// todo: slashing functionality
// todo: figure out token moving
abstract contract EigenLayrDepositStorage {
    bytes32 public withdrawalCredentials;
    bytes32 public constant legacyDepositPermissionMessage =
        0x656967656e4c61797252657374616b696e67596f754b6e6f7749744261626179;
    IDepositContract public depositContract;
    QueryManager public posMiddleware;
    mapping(IERC20 => bool) public isAllowedLiquidStakedToken;
    mapping(bytes32 => mapping(address => bool)) public depositProven;
    IInvestmentManager public investmentManager;
    uint256 constant eigenTokenId = 0;
}