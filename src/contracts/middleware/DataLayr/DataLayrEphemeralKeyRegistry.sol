// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrEphemeralKeyRegistry.sol";
import "./DataLayrRegistry.sol";

contract DataLayrEphemeralKeyRegistry is IDataLayrEphemeralKeyRegistry{
    struct HashEntry{
        bytes32 keyHash;
        uint timestamp;
    }
    struct EKEntry{
        bytes32 EK;
        uint timestamp;
    }
    mapping(address=>HashEntry) public EKRegistry;
    mapping(address => EKEntry) public latestEk;

    

    uint256 public updatePeriod = 7 days;

    IRepository public immutable repository;

    constructor(IRepository _repository){
        repository = _repository;
    }

    /*
    * Allows DLN to post their first ephemeral key hash via DataLayrRegistry
    */
    function postFirstEphemeralKeyPreImage(address operator, bytes32 EKHash) external {
        require(EKRegistry[operator].keyHash==0, "previous ephemeral key already exists");
        EKRegistry[operator].keyHash = EKHash;
        EKRegistry[operator].timestamp = block.timestamp;
    }

    /*
    * Allows DLN to post their final ephemeral key hash via DataLayrRegistry
    */
    function postLastEphemeralKeyPreImage(address operator, bytes32 EK) external {
        latestEk[operator].EK = EK;
        latestEk[operator].timestamp = block.timestamp;
    }

     /*
    * Allows DLN to update their ephemeral key hash and post their previous ephemeral key 
    */
    function updateEphemeralKeyPreImage(bytes32 prevEK, bytes32 currEKHash) external {
        require(keccak256(abi.encodePacked(prevEK)) == EKRegistry[msg.sender].keyHash, "Ephemeral key does not match previous ephemeral key commitment");

        require(block.timestamp <= EKRegistry[msg.sender].timestamp + updatePeriod, "key update cannot be completed as update window has expired");

        EKRegistry[msg.sender].keyHash = currEKHash;
        EKRegistry[msg.sender].timestamp = block.timestamp;

        latestEk[msg.sender].EK = prevEK;
        latestEk[msg.sender].timestamp = block.timestamp;
    }


    /*
    * retrieve a DLN's current EK hash
    */
    function getCurrEphemeralKeyHash(address dataLayrNode) external view returns (bytes32){
        return EKRegistry[dataLayrNode].keyHash;
    }


    function getLatestEphemeralKey(address dataLayrNode)
        external view
        returns (bytes32)
    {
        return latestEk[dataLayrNode].EK;
    }

    /*
    *proof for DLN that hasn't updated their ephemeral key within the update window.  
    */
    function proveStaleEphemeralKey(address dataLayrNode) external {
        IDataLayrRegistry dlRegistry = IDataLayrRegistry(address(repository.registrationManager()));

        //check if DLN is still active in the DLRegistry
        require(dlRegistry.getDLNStatus(dataLayrNode) == 1, "DLN not active");

        if(EKRegistry[dataLayrNode].timestamp + 7 days < block.timestamp){
            //trigger slashing for DLN who hasn't updated their EK
        }

    }

    
    /*
    * proof for DLN who's ephemeral key has been leaked
    */
    function verifyEphemeralKeyIntegrity(address dataLayrNode, bytes32 leakedEphemeralKey) external {
        
        if(EKRegistry[dataLayrNode].keyHash==keccak256(abi.encode(leakedEphemeralKey))){
            //trigger slashing function for that datalayr node address
        }
    }


    function getLastEKPostTimestamp(address dataLayrNode) external view returns (uint) {
        return latestEk[dataLayrNode].timestamp;
    }

}
