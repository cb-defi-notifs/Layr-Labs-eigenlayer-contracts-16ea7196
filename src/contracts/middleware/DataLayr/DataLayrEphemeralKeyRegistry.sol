// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrEphemeralKeyRegistry.sol";

contract DataLayrEphemeralKeyRegistry {
    mapping(address => bytes32) public ekRegistry;
    mapping(address => bytes32) public latestEk;

    constructor() {}

    /*
     * Allows DLN to post their first ephemeral key hash
     */

    function postFirstEphemeralKeyPreImage(bytes32 ekHash) public {
        require(
            ekRegistry[msg.sender] == 0,
            "previous ephemeral key already exists"
        );
        ekRegistry[msg.sender] = ekHash;
    }

    function updateEphemeralKeyPreImage(bytes32 prevEk, bytes32 currEkHash)
        public
    {
        require(
            keccak256(abi.encodePacked(prevEk)) == ekRegistry[msg.sender],
            "Ephemeral key does not match previous ephemeral key commitment"
        );

        ekRegistry[msg.sender] = currEkHash;
        latestEk[msg.sender] = prevEk;
    }

    function getCurrEphemeralKeyHash(address dataLayrNode)
        public
        returns (bytes32)
    {
        return ekRegistry[dataLayrNode];
    }

    function getLatestEphemeralKey(address dataLayrNode)
        public
        returns (bytes32)
    {
        return latestEk[dataLayrNode];
    }

    function verifyEphemeralKeyIntegrity(bytes memory ephemeralKey) public {}
}
