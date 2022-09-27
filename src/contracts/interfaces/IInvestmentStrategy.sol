// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Minimal interface for an `InvestmentStrategy` contract.
 * @author Layr Labs, Inc.
 * @notice Custom `InvestmentStrategy` implementations may expand extensively on this interface.
 */
interface IInvestmentStrategy {
    function explanation() external returns (string memory);

    function deposit(IERC20 token, uint256 amount) external returns (uint256);

    function withdraw(address depositor, IERC20 token, uint256 amount) external;

    function sharesToUnderlying(uint256 numShares) external returns (uint256);
    function sharesToUnderlyingView(uint256 numShares) external view returns (uint256);
    function underlyingToken() external view returns (IERC20);
    function totalShares() external view returns (uint256);

    event Deposit(address indexed from);
    event Withdraw(address indexed to);
}
