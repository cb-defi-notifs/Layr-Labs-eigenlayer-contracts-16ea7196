// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/**
 * @title Interface for factory that creates and manages solo staking pods that have their withdrawal credentials pointed to EigenLayer.
 * @author Layr Labs, Inc.
 */

interface IEigenPodManager {
    function stake(bytes32 salt, bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable;
    function updateBeaconChainBalance(address podOwner, uint64 balanceToRemove, uint64 balanceToAdd) external;
    function depositBalanceIntoEigenLayer(address podOwner, uint128 amount) external;
}
