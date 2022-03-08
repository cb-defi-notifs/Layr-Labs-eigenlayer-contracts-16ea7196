// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IInvestmentStrategy.sol";

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