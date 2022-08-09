// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IInvestmentStrategy.sol";
import "./ISlasher.sol";

interface IInvestmentManager {

    function depositIntoStrategy(
        address depositor,
        IInvestmentStrategy strategies,
        IERC20 token,
        uint256 amount
    ) external returns (uint256);

    function withdrawFromStrategy(
        uint256 strategyIndex,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 shareAmount
    ) external;

    function getStrategyShares(address depositor)
        external
        view
        returns (uint256[] memory);

    function getStrategies(address depositor)
        external
        view
        returns (IInvestmentStrategy[] memory);

    function investorStratShares(address user, IInvestmentStrategy strategy)
        external
        view
        returns (uint256 shares);

    function getUnderlyingValueOfStrategyShares(
        IInvestmentStrategy[] calldata strats,
        uint256[] calldata shares
    ) external returns (uint256);

    function getUnderlyingValueOfStrategySharesView(
        IInvestmentStrategy[] calldata strats,
        uint256[] calldata shares
    ) external returns (uint256);

    function getDeposits(address depositor)
        external
        view
        returns (
            IInvestmentStrategy[] memory,
            uint256[] memory
        );

    function slasher() external view returns (ISlasher);

    function slashedStatus(address operator) external view returns (bool);
}
