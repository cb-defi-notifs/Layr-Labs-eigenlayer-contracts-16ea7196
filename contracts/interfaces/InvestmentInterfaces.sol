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
        uint256 shares
    ) external;

    function withdrawFromStrategies(
        address depositor,
        uint256[] calldata strategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shares
    ) external;

    function depositConsenusLayerEth(
        address depositor,
        uint256 amount
    ) external returns (uint256);

    function getStrategyShares(address depositor)
        external view
        returns (uint256[] memory);

    function getStrategies(address depositor)
        external view
        returns (IInvestmentStrategy[] memory);

    function getConsensusLayerEth(address depositor)
        external view
        returns (uint256);

    function investorStratShares(address user, IInvestmentStrategy strategy)
        external view
        returns (uint256 shares);

    function consensusLayerEth(address user)
        external view
        returns (uint256);

    function getUnderlyingEthStaked(address depositor)
        external
        returns (uint256);

    function getUnderlyingEthStakedView(address staker)
        external view
        returns (uint256);
}

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
