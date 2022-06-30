// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrEphemeralKeyRegistry.sol";
import "./DataLayrRegistry.sol";

// TODO: need to add minimum window for update
// TODO: MAJOR CRITIQUE -- we need nonoverlapping windows for 'updateEphemeralKeyPreImage' and 'verifyEphemeralKeyIntegrity'
    // as-is, someone can frontrun a transaction to 'updateEphemeralKeyPreImage' by calling 'verifyEphemeralKeyIntegrity' to slash an honest operator
contract DataLayrEphemeralKeyRegistry is IDataLayrEphemeralKeyRegistry{
    struct HashEntry{
        bytes32 keyHash;
        uint256 timestamp;
    }
    struct EKEntry{
        bytes32 EK;
        uint256 timestamp;
    }

    // max amount of time that a DLN can take to update their ephemeral key
    uint256 public constant UPDATE_PERIOD = 7 days;

    //max amout of time DLN has to submit and confirm the ephemeral key reveal transaction
    uint256 public constant REVEAL_PERIOD = 1 days;
    
    // the DataLayr Repository contract
    IRepository public immutable repository;

    mapping(address => HashEntry) public EKRegistry;
    mapping(address => EKEntry) public latestEK;

    modifier onlyDLRegistry() {
        address dlRegistry = address(repository.registrationManager());
        require(msg.sender == dlRegistry, "onlyDLRegistry");
        _;
    }

    constructor(IRepository _repository){
        repository = _repository;
    }

    /*
    * Allows DLN to post their first ephemeral key hash via DataLayrRegistry (on registration)
    */
    function postFirstEphemeralKeyHash(address operator, bytes32 EKHash) external onlyDLRegistry {
        require(EKRegistry[operator].keyHash == 0, "previous ephemeral key already exists");
        EKRegistry[operator].keyHash = EKHash;
        EKRegistry[operator].timestamp = block.timestamp;
    }

    /*
    * Allows DLN to post their final ephemeral key preimage via DataLayrRegistry (on degregistration)
    */
    function postLastEphemeralKeyPreImage(address operator, bytes32 EK) external onlyDLRegistry {
        latestEK[operator].EK = EK;
        latestEK[operator].timestamp = block.timestamp;
    }

     /*
    * Allows DLN to update their ephemeral key hash and post their previous ephemeral key 
    */
    function updateEphemeralKeyPreImage(bytes32 prevEK, bytes32 currEKHash) external {
        require(keccak256(abi.encodePacked(prevEK)) == EKRegistry[msg.sender].keyHash, "Ephemeral key does not match previous ephemeral key commitment");

        require(block.timestamp <= EKRegistry[msg.sender].timestamp + UPDATE_PERIOD, "key update cannot be completed as update window has expired");

        EKRegistry[msg.sender].keyHash = currEKHash;
        EKRegistry[msg.sender].timestamp = block.timestamp;

        latestEK[msg.sender].EK = prevEK;
        latestEK[msg.sender].timestamp = block.timestamp;
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
        return latestEK[dataLayrNode].EK;
    }

    /*
    *proof for DLN that hasn't updated their ephemeral key within the update window.  
    */
    function proveStaleEphemeralKey(address dataLayrNode) external {
        IDataLayrRegistry dlRegistry = IDataLayrRegistry(address(repository.registrationManager()));

        //check if DLN is still active in the DLRegistry
        require(dlRegistry.getDLNStatus(dataLayrNode) == 1, "DLN not active");

        if((EKRegistry[dataLayrNode].timestamp + UPDATE_PERIOD + REVEAL_PERIOD) < block.timestamp) {
            // TODO: add slashing
            //trigger slashing for DLN who hasn't updated their EK
        }

    }

    
    /*
    * proof for DLN who's ephemeral key has been leaked
    */
    function verifyEphemeralKeyIntegrity(address dataLayrNode, bytes32 leakedEphemeralKey) external {
        
        if (block.timestamp < EKRegistry[dataLayrNode].timestamp + UPDATE_PERIOD){
            if (EKRegistry[dataLayrNode].keyHash == keccak256(abi.encode(leakedEphemeralKey))) {
                //trigger slashing function for that datalayr node address
            }
        }
    }


    function getLastEKPostTimestamp(address dataLayrNode) external view returns (uint) {
        return latestEK[dataLayrNode].timestamp;
    }

}
