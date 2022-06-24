// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrEphemeralKeyRegistry.sol";
import "./DataLayrRegistry.sol";

contract DataLayrEphemeralKeyRegistry {
    mapping(address => bytes32) public ekRegistry;
    mapping(address => bytes32) public latestEk;

    struct HashEntry{
        bytes32 keyHash;
        uint timestamp;
    }

    mapping(address=>HashEntry) public EKRegistry;
    uint256 public updatePeriod = 7 days;

    IRepository public repository;
    IDataLayrRegistry public dlRegistry;

    
    constructor(){
        dlRegistry = IDataLayrRegistry(address(repository.registrationManager()));
    }

    /*
    * Allows DLN to post their first ephemeral key hash via DataLayrRegistry
    */
    function postFirstEphemeralKeyPreImage(address operator, bytes32 EKHash) public {
        require(EKRegistry[operator].keyHash==0, "previous ephemeral key already exists");
        EKRegistry[operator].keyHash = EKHash;
        EKRegistry[operator].timestamp = block.timestamp;
    }

     /*
    * Allows DLN to update their ephemeral key hash and post their previous ephemeral key 
    */
    function updateEphemeralKeyPreImage(bytes32 prevEK, bytes32 currEKHash) public {
        require(keccak256(abi.encodePacked(prevEK)) == EKRegistry[msg.sender].keyHash, "Ephemeral key does not match previous ephemeral key commitment");

        require(block.timestamp <= EKRegistry[msg.sender].timestamp + updatePeriod, "key update cannot be completed as update window has expired");

        EKRegistry[msg.sender].keyHash = currEKHash;
        EKRegistry[msg.sender].timestamp = block.timestamp;

        latestEk[msg.sender] = prevEK;
    }


    /*
    * retrieve a DLN's current EK hash
    */
    function getCurrEphemeralKeyHash(address dataLayrNode) public view returns (bytes32){
        return EKRegistry[dataLayrNode].keyHash;
    }


    function getLatestEphemeralKey(address dataLayrNode)
        public
        returns (bytes32)
    {
        return latestEk[dataLayrNode];
    }

    /*
    *proof for DLN that hasn't updated their ephemeral key within the update window.  
    */
    function proveStaleEphemeralKey(address dataLayrNode) public{
        
        //check if DLN is still active in the DLRegistry
        require(dlRegistry.registry(dataLayrNode).active == 1, "DLN not active");

        if(EKRegistry[dataLayrNode].timestamp + 7 days < block.timestamp){
            //trigger slashing for DLN who hasn't updated their EK
        }

    }

    
    /*
    * proof for DLN who's ephemeral key has been leaked
    */
    function verifyEphemeralKeyIntegrity(address dataLayrNode, bytes32 leakedEphemeralKey) public {
        
        if(EKRegistry[dataLayrNode].keyHash==keccak256(leakedEphemeralKey)){
            //trigger slashing function for that datalayr node address
        }
    }

}
