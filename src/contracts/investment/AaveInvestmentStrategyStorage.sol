// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IInvestmentManager.sol";
import "./aave/ILendingPool.sol";

abstract contract AaveInvestmentStrategyStorage {
    ILendingPool public lendingPool;
    IERC20 public underlyingToken;
    IERC20 public aToken;
    address public investmentManager;
    uint256 public totalShares;
}
