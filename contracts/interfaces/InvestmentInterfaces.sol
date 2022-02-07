// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC20.sol";

interface IInvestmentManager {
    function addInvestmentStrategies(IInvestmentStrategy[] calldata strategies)
        external;

    function removeInvestmentStrategies(
        IInvestmentStrategy[] calldata strategies
    ) external;

    function depositIntoStrategy(
        address depositer,
        IInvestmentStrategy strategies,
        IERC20 token,
        uint256 amount
    ) external returns (uint256);

    function depositIntoStrategies(
        address depositer,
        IInvestmentStrategy[] calldata strategies,
        IERC20[][] calldata tokens,
        uint256[][] calldata amounts
    ) external returns (uint256[] memory);

    function withdrawFromStrategies(
        address depositer,
        uint256[] calldata strategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[][] calldata tokens,
        uint256[][] calldata amounts
    ) external;

    function getStrategyShares(address depositer, IInvestmentStrategy[] calldata strategies)
        external
        returns (uint256[] memory);
}

interface IInvestmentStrategy {
    function explanation() external returns (string memory);

    function deposit(
        address depositer,
        IERC20[] calldata tokens,
        uint256[] calldata amounts
    ) external returns (uint256);

    function depositSingle(
        address depositer,
        IERC20 token,
        uint256 amount
    ) external returns (uint256);

    function withdraw(
        address depositer,
        IERC20[] calldata tokens,
        uint256[] calldata amounts
    ) external returns (uint256);

    event Deposit(address indexed from);
    event Withdraw(address indexed to);
}
