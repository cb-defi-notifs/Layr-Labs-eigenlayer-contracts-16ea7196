// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/**
 * @title Interface for solo staking pods that have their withdrawal credentials pointed to EigenLayer.
 * @author Layr Labs, Inc.
 */

interface IEigenPod {
    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable;
}
