// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./InvestmentInterfaces.sol";

interface IEigenLayrDeposit {
    function depositETHIntoLiquidStaking(
        IERC20 liquidStakeToken,
        IInvestmentStrategy strategy
    ) external payable;

    function depositPOSProof(
        bytes32[] calldata treeProof,
        bool[] calldata flags,
        uint256 numBranchFlags,
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata signature,
        uint64 stake
    ) external;

    function depositEthIntoConsensusLayer(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable;
}

interface IEigenLayrDelegation {
    function registerAsDelgate(IDelegationTerms dt) external;
    function commitUndelegation() external;
    
}

interface IDelegationTerms {
    function onDelegationReceived(address node, IInvestmentStrategy[] calldata strategies, uint256[] calldata shares) external;
    function onDelegationWithdrawn(address node, IInvestmentStrategy[] calldata strategies, uint256[] calldata shares) external;
}