// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import "./IERC20.sol";

interface IInvestmentManager {
    function addInvestmentStrategies(IInvestmentStrategy[] calldata strategies)
        external;

    function removeInvestmentStrategies(
        IInvestmentStrategy[] calldata strategies
    ) external;

    function depositIntoStrategies(
        address depositer,
        IInvestmentStrategy[] calldata strategies,
        IERC20[][] calldata tokens,
        uint256[][] calldata amounts
    ) external returns (uint256[] memory);

    function withdrawFromStrategies(
        address depositer,
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

    function withdraw(
        address depositer,
        IERC20[] calldata tokens,
        uint256[] calldata amounts
    ) external returns (uint256);

    event Deposit(address indexed from);
    event Withdraw(address indexed to);
}
