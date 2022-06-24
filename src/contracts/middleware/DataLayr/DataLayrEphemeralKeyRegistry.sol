// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


import "../../interfaces/IDataLayrEphemeralKeyRegistry.sol";

contract DataLayrEphemeralKeyRegistry {

    mapping(address=>bytes32) public EKRegistry;


    constructor(){}

    /*
    * Allows DLN to post their first ephemeral key hash
    */

    function postFirstEphemeralKeyPreImage(bytes32 EKHash) public {
        require(EKRegistry[msg.sender]==0, "previous ephemeral key already exists");
        EKRegistry[msg.sender] = EKHash;
    }

    function updateEphemeralKeyPreImage(bytes memory prevEK, bytes32 currEKHash) public {
        require(keccak256(prevEK) == EKRegistry[msg.sender], "Ephemeral key does not match previous ephemeral key commitment");

        EKRegistry[msg.sender] = currEKHash;
    }

    function getCurrEphemeralKeyHash(address dataLayrNode) public returns (bytes32){
        return EKRegistry[dataLayrNode];

    }

    function verifyEphemeralKeyIntegrity(bytes memory ephemeralKey) public {

    }

}