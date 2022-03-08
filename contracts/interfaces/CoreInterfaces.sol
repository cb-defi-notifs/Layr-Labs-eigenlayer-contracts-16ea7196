// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./InvestmentInterfaces.sol";
import "./MiddlewareInterfaces.sol";

interface IEigenLayrDeposit {
    function depositETHIntoLiquidStaking(
        IERC20 liquidStakeToken,
        IInvestmentStrategy strategy
    ) external payable;

    function depositPOSProof(
        bytes32 queryHash,
        bytes32[] calldata proof,
        address depositer,
        bytes calldata signature,
        uint256 amount
    ) external;

    function depositEthIntoConsensusLayer(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable;
}

interface IEigenLayrDelegation {
    function registerAsDelgate(IDelegationTerms dt) external;

    function getDelegationTerms(address operator)
        external
        view
        returns (IDelegationTerms);

    function getOperatorShares(address operator)
        external
        view
        returns (IInvestmentStrategy[] memory);

    function getUnderlyingEthDelegated(address operator)
        external
        returns (uint256);

    function getUnderlyingEthDelegatedView(address operator)
        external
        view
        returns (uint256);

    function getConsensusLayerEthDelegated(address operator)
        external
        view
        returns (uint256);
    
    function getEigenDelegated(address operator)
        external
        view
        returns (uint256)
}

interface IDelegationTerms {
    function payForService(
        IQueryManager queryManager,
        IERC20[] calldata tokens,
        uint256[] calldata amounts
    ) external payable;

    function onDelegationWithdrawn(
        address staker,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata shares
    ) external;

    function onDelegationReceived(
        address staker,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata shares
    ) external;
}
