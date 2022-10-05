// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IQuorumRegistry.sol";

/**
 * @title Minimal interface extension to `IQuorumRegistry`.
 * @author Layr Labs, Inc.
 * @notice Adds a single BLS-specific function to the base interface.
 */
interface IBLSRegistry is IQuorumRegistry {
    function getCorrectApkHash(uint256 index, uint32 blockNumber) external returns (bytes32);
}
