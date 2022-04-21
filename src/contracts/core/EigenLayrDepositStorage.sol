// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Eigen.sol";
import "../interfaces/IDepositContract.sol";
import "../interfaces/IInvestmentManager.sol";
import "../middleware/Repository.sol";

abstract contract EigenLayrDepositStorage {
    bytes32 public withdrawalCredentials;
    bytes32 public constant legacyDepositPermissionMessage =
        0x656967656e4c61797252657374616b696e67596f754b6e6f7749744261626179;
    IDepositContract public depositContract;
    Repository public posMiddleware;
    mapping(IERC20 => bool) public isAllowedLiquidStakedToken;
    mapping(bytes32 => mapping(address => bool)) public depositProven;
    IInvestmentManager public investmentManager;
}