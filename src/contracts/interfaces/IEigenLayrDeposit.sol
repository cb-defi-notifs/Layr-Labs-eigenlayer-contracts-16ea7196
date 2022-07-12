// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IInvestmentStrategy.sol";

interface IEigenLayrDeposit {
    function depositETHIntoLiquidStaking(
        IERC20 ,
        IInvestmentStrategy
    ) external payable;

    // function depositPOSProof(
    //     uint256,
    //     bytes32[] calldata,
    //     address,
    //     bytes calldata,
    //     uint256
    // ) external;

    // function depositEthIntoConsensusLayer(
    //     bytes calldata,
    //     bytes calldata,
    //     bytes32
    // ) external payable;
}