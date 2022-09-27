// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IBLSPublicKeyCompendium.sol";
import "../libraries/BLS.sol";

/**
 * @title An shared contract for EigenLayer operators to register their BLS public keys.
 * @author Layr Labs, Inc.
 */
contract BLSPublicKeyCompendium is IBLSPublicKeyCompendium {

    mapping(bytes32 => address) public pubkeyHashToOperator;

    /// @notice Emitted when `operator` registers with the BLS public key `pk`, that has hash `pkh`.
    event NewPubkeyRegistration(address operator, uint256[4] pk, bytes32 pkh);

    /**
     * @notice Called by an operator to register themselves as the owner of a BLS public key.
     * @param data is the calldata that contains the coordinates for pubkey on G2 and signature on G1.
     */
    function registerBLSPublicKey(bytes calldata data)
        external
    {
        uint256[4] memory pk;

        // verify sig of public key and get pubkeyHash back, slice out compressed apk
        (pk[0], pk[1], pk[2], pk[3]) = BLS.verifyBLSSigOfPubKeyHash(data, msg.sender);

        // getting pubkey hash
        bytes32 pubkeyHash = keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3]));
        
        require(pubkeyHashToOperator[pubkeyHash] == address(0), "BLSPublicKeyRegistry.registerBLSPublicKey: public key already registered");

        //store updates
        pubkeyHashToOperator[pubkeyHash] = msg.sender;

        //emit event of new regsitratio
        emit NewPubkeyRegistration(msg.sender, pk, pubkeyHash);
    }
}
