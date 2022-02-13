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
    function getDelegationTerms(address operator) external view returns(IDelegationTerms);
    function getOperatorShares(address operator) external view returns(IInvestmentStrategy[] memory);
}

interface IDelegationTerms {
    function payForService(IQueryManager queryManager, IERC20[] calldata tokens, uint256[] calldata amounts) external payable;
    function onDelegationWithdrawn(address staker, IInvestmentStrategy[] calldata strategies, uint256[] calldata shares) external;
    function onDelegationReceived(address staker, IInvestmentStrategy[] calldata strategies, uint256[] calldata shares) external;
}