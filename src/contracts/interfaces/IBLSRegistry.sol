// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IQuorumRegistry.sol";

/**
 * @title Minimal interface extension to `IQuorumRegistry`.
 * @author Layr Labs, Inc.
 * @notice Adds BLS-specific functions to the base interface.
 */
interface IBLSRegistry is IQuorumRegistry {
    struct ApkUpdate {
        bytes32 apkHash;
        uint32 blockNumber;
    }

    /**
     * @notice get hash of a historical aggregated public key corresponding to a given index;
     * called by checkSignatures in BLSSignatureChecker.sol.
     */
    function getCorrectApkHash(uint256 index, uint32 blockNumber) external returns (bytes32);

    /// @notice returns the `ApkUpdate` struct at `index` in the list of APK updates
    function apkUpdates(uint256 index) external view returns (ApkUpdate memory);

    /// @notice returns the APK hash that resulted from the `index`th APK update
    function apkHashes(uint256 index) external view returns (bytes32);

    /// @notice returns the block number at which the `index`th APK update occurred
    function apkUpdateBlockNumbers(uint256 index) external view returns (uint32);
}
