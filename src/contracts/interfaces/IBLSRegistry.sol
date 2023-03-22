// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "./IQuorumRegistry.sol";

/**
 * @title Minimal interface extension to `IQuorumRegistry`.
 * @author Layr Labs, Inc.
 * @notice Adds BLS-specific functions to the base interface.
 */
interface IBLSRegistry is IQuorumRegistry {
    /// @notice Data structure used to track the history of the Aggregate Public Key of all operators
    struct ApkUpdate {
        // keccak256(apk_x0, apk_x1, apk_y0, apk_y1)
        bytes32 apkHash;
        // block number at which the update occurred
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

    function whitelister() external view returns(address);

    function whitelistEnabled() external view returns(bool);

    function whitelisted(address) external view returns(bool);

    function setWhitelistStatus(bool _whitelistEnabled) external;

    function addToWhitelist(address[] calldata) external;

    function removeFromWhitelist(address[] calldata operators) external;
}