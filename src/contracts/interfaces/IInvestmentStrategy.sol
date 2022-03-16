// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC20.sol";

interface IInvestmentStrategy {
    function explanation() external returns (string memory);

    function deposit(
        IERC20 token,
        uint256 amount
    ) external returns (uint256);

    function withdraw(
        address depositor,
        IERC20 token,
        uint256 amount
    ) external returns (uint256);

    function underlyingEthValueOfShares(uint256 numShares) external returns(uint256);
    function underlyingEthValueOfSharesView(uint256 numShares) external view returns(uint256);

    event Deposit(address indexed from);
    event Withdraw(address indexed to);
}