// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IQuorumRegistry.sol";

/**
 * @title Minimal interface extension to `IQuorumRegistry`.
 * @author Layr Labs, Inc.
 * @notice Adds a single ECDSA-specific function to the base interface.
 */
interface IECDSARegistry is IQuorumRegistry {
    function getCorrectStakeHash(uint256 index, uint32 blockNumber) external returns (bytes32);
}
