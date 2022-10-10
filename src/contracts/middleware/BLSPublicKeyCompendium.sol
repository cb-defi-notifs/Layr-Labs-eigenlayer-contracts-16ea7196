// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IBLSPublicKeyCompendium.sol";
import "../libraries/BLS.sol";
import "forge-std/Test.sol";

/**
 * @title A shared contract for EigenLayer operators to register their BLS public keys.
 * @author Layr Labs, Inc.
 */
contract BLSPublicKeyCompendium is IBLSPublicKeyCompendium, DSTest {
    //Hash of the zero public key
    bytes32 internal constant ZERO_PK_HASH = hex"012893657d8eb2efad4de0a91bcd0e39ad9837745dec3ea923737ea803fc8e3d";

    mapping(address => bytes32) public operatorToPubkeyHash;
    mapping(bytes32 => address) public pubkeyHashToOperator;

    // EVENTS
    event NewPubkeyRegistration(address operator, uint256[4] pk);

    /**
     * @notice Called by an operator to register themselves as the owner of a BLS public key.
     * @param data is the calldata that contains the coordinates for pubkey on G2 and signature on G1.
     */
    function registerBLSPublicKey(bytes calldata data) external {
        uint256[4] memory pk;

        // verify sig of public key and get pubkeyHash back, slice out compressed apk
        (pk[0], pk[1], pk[2], pk[3]) = BLS.verifyBLSSigOfPubKeyHash(data, msg.sender);

        // getting pubkey hash
        bytes32 pubkeyHash = BLS.hashPubkey(pk);

        require(
            pubkeyHash != ZERO_PK_HASH,
            "BLSPublicKeyCompendium.registerBLSPublicKey: Cannot register with 0x0 public key"
        );

        require(
            operatorToPubkeyHash[msg.sender] == bytes32(0),
            "BLSPublicKeyCompendium.registerBLSPublicKey: operator already registered pubkey"
        );
        require(
            pubkeyHashToOperator[pubkeyHash] == address(0),
            "BLSPublicKeyCompendium.registerBLSPublicKey: public key already registered"
        );

        // store updates
        operatorToPubkeyHash[msg.sender] = pubkeyHash;
        pubkeyHashToOperator[pubkeyHash] = msg.sender;

        // emit event of new regsitration
        emit NewPubkeyRegistration(msg.sender, pk);
    }
}
