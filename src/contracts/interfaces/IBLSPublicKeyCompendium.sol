// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/**
 * @title Minimal interface for the `BLSPublicKeyCompendium` contract.
 * @author Layr Labs, Inc.
 */
interface IBLSPublicKeyCompendium {
    /// @notice mapping from operator addresss to pubkey hash
    function operatorToPubkeyHash(address operator) external view returns (bytes32);

    /// @notice mapping from pubkey hash to operator addresss
    function pubkeyHashToOperator(bytes32 pubkeyHash) external view returns (address);

    /**
     * @notice Called by an operator to register themselves as the owner of a BLS public key.
     * @param data is the calldata that contains the coordinates for pubkey on G2 and signature on G1.
     */
    function registerBLSPublicKey(bytes calldata data) external;
}
