// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/**
 * @title Minimal interface extension to `IBLSPublicKeyCompendium`.
 * @author Layr Labs, Inc.
 */
interface IBLSPublicKeyCompendium {
    function operatorToPubkeyHash(address operator) external view returns (bytes32);
    function pubkeyHashToOperator(bytes32 pubkeyHash) external view returns (address);
    function registerBLSPublicKey(bytes calldata data) external;
}
