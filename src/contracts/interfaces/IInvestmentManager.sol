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

    function investorStratShares(address user, IInvestmentStrategy strategy)
        external
        view
        returns (uint256 shares);

    function getDeposits(address depositor)
        external
        view
        returns (
            IInvestmentStrategy[] memory,
            uint256[] memory
        );

    function slasher() external view returns (ISlasher);
}
