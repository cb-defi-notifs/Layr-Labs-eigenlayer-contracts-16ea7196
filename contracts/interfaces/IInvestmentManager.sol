// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IInvestmentStrategy.sol";

interface IInvestmentManager {
    function addInvestmentStrategies(IInvestmentStrategy[] calldata strategies)
        external;

    function removeInvestmentStrategies(
        IInvestmentStrategy[] calldata strategies
    ) external;

    function depositIntoStrategy(
        address depositor,
        IInvestmentStrategy strategies,
        IERC20 token,
        uint256 amount
    ) external payable returns (uint256);

    function depositIntoStrategies(
        address depositor,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata amounts
    ) external payable returns (uint256[] memory);

    function withdrawFromStrategy(
        address depositor,
        uint256 strategyIndex,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 shareAmount
    ) external;

    function withdrawFromStrategies(
        address depositor,
        uint256[] calldata strategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts
    ) external;

    function depositConsenusLayerEth(address depositor, uint256 amount)
        external
        returns (uint256);

    function depositEigen(address depositor, uint256 amount)
        external
        returns (uint256);

    function getStrategyShares(address depositor)
        external
        view
        returns (uint256[] memory);

    function getStrategies(address depositor)
        external
        view
        returns (IInvestmentStrategy[] memory);

    function getConsensusLayerEth(address depositor)
        external
        view
        returns (uint256);

    function getEigen(address depositor) external view returns (uint256);

    function getDeposits(address depositor)
        external
        view
        returns (
            IInvestmentStrategy[] memory,
            uint256[] memory,
            uint256,
            uint256
        );

    function investorStratShares(address user, IInvestmentStrategy strategy)
        external
        view
        returns (uint256 shares);

    function getUnderlyingEthStaked(address depositor)
        external
        returns (uint256);

    function getUnderlyingEthStakedView(address staker)
        external
        view
        returns (uint256);

    function getNfgtStaked(address depositor) external view returns (uint256);

    function getUnderlyingEthOfStrategyShares(
        IInvestmentStrategy[] calldata strats,
        uint256[] calldata shares
    ) external returns (uint256);

    function getUnderlyingEthOfStrategySharesView(
        IInvestmentStrategy[] calldata strats,
        uint256[] calldata shares
    ) external returns (uint256);
}
