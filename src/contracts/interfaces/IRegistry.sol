// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9.0;

/**
 * @title Minimal interface for a `Registry`-type contract.
 * @author Layr Labs, Inc.
 * @notice Functions related to the registration process itself have been intentionally excluded
 * because their function signatures may vary significantly.
 */
interface IRegistry {
    function isRegistered(address operator) external view returns (bool);
}
