// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IInvestmentStrategy.sol";

interface IInvestmentManager {

    function consensusLayerEthStrat() view external returns(IInvestmentStrategy);

    function proofOfStakingEthStrat() view external returns(IInvestmentStrategy);

    function depositIntoStrategy(
        address depositor,
        IInvestmentStrategy strategies,
        IERC20 token,
        uint256 amount
    ) external returns (uint256);

    function depositIntoStrategies(
        address depositor,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata amounts
    ) external returns (uint256[] memory);

    function withdrawFromStrategy(
        uint256 strategyIndex,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 shareAmount
    ) external;

    function withdrawFromStrategies(
        uint256[] calldata strategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts
    ) external;

    function getStrategyShares(address depositor)
        external
        view
        returns (uint256[] memory);

    function getStrategies(address depositor)
        external
        view
        returns (IInvestmentStrategy[] memory);

    function depositConsenusLayerEth(address depositor, uint256 amount)
        external
        returns (uint256);

    function depositProofOfStakingEth(address depositor, uint256 amount)
        external
        returns (uint256);

    function depositEigen(uint256 amount)
        external
        returns (uint256);

    function getConsensusLayerEth(address depositor)
        external
        view
        returns (uint256);

    function getEigen(address depositor) external view returns (uint256);

    function investorStratShares(address user, IInvestmentStrategy strategy)
        external
        view
        returns (uint256 shares);

    function getUnderlyingEthOfStrategyShares(
        IInvestmentStrategy[] calldata strats,
        uint256[] calldata shares
    ) external returns (uint256);

    function getUnderlyingEthOfStrategySharesView(
        IInvestmentStrategy[] calldata strats,
        uint256[] calldata shares
    ) external returns (uint256);
}
