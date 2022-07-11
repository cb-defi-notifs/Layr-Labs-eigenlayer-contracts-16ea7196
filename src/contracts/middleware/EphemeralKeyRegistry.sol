// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IEphemeralKeyRegistry.sol";
import "../permissions/RepositoryAccess.sol";

contract EphemeralKeyRegistry is IEphemeralKeyRegistry, RepositoryAccess {
    struct HashEntry {
        bytes32 keyHash;
        uint256 timestamp;
    }
    struct EKEntry {
        bytes32 EK;
        uint256 timestamp;
    }

    // max amount of time that an operator can take to update their ephemeral key
    uint256 public constant UPDATE_PERIOD = 7 days;

    //max amout of time operator has to submit and confirm the ephemeral key reveal transaction
    uint256 public constant REVEAL_PERIOD = 7 days;

    mapping(address => HashEntry) public EKRegistry;
    mapping(address => EKEntry) public latestEK;

    constructor(IRepository _repository)
        RepositoryAccess(_repository)
    {
    }

    /*
    * Allows operator to post their first ephemeral key hash via BLSRegistry (on registration)
    */
    function postFirstEphemeralKeyHash(address operator, bytes32 EKHash) external onlyRegistry {
        require(EKRegistry[operator].keyHash == 0, "previous ephemeral key already exists");
        EKRegistry[operator].keyHash = EKHash;
        EKRegistry[operator].timestamp = block.timestamp;
    }

    /*
    * Allows operator to post their final ephemeral key preimage via BLSRegistry (on degregistration)
    */
    function postLastEphemeralKeyPreImage(address operator, bytes32 EK) external onlyRegistry {
        latestEK[operator].EK = EK;
        latestEK[operator].timestamp = block.timestamp;
    }

     /*
    * Allows operator to update their ephemeral key hash and post their previous ephemeral key 
    */
    function updateEphemeralKeyPreImage(bytes32 prevEK, bytes32 currEKHash) external {
        require(keccak256(abi.encodePacked(prevEK)) == EKRegistry[msg.sender].keyHash, "Ephemeral key does not match previous ephemeral key commitment");

        require(block.timestamp >= EKRegistry[msg.sender].timestamp + UPDATE_PERIOD, "key update cannot be completed too early");
        require(block.timestamp <= EKRegistry[msg.sender].timestamp + UPDATE_PERIOD + REVEAL_PERIOD, "key update cannot be completed as update window has expired");

        EKRegistry[msg.sender].keyHash = currEKHash;
        EKRegistry[msg.sender].timestamp = block.timestamp;

        latestEK[msg.sender].EK = prevEK;
        latestEK[msg.sender].timestamp = block.timestamp;
    }

    /*
    * retrieve a operator's current EK hash
    */
    function getCurrEphemeralKeyHash(address operator) external view returns (bytes32){
        return EKRegistry[operator].keyHash;
    }


    function getLatestEphemeralKey(address operator)
        external view
        returns (bytes32)
    {
        return latestEK[operator].EK;
    }

    /*
    *proof for operator that hasn't updated their ephemeral key within the update window.  
    */
    function proveStaleEphemeralKey(address operator) external {
        IRegistry registry = repository.registry();

        //check if operator is still active in the DLRegistry
        require(registry.getOperatorStatus(operator) == 1, "operator not active");

        if((block.timestamp > EKRegistry[operator].timestamp + UPDATE_PERIOD + REVEAL_PERIOD)) {
            IServiceManager serviceManager = repository.serviceManager();
            //trigger slashing for operator who hasn't updated their EK
            serviceManager.slashOperator(operator);
        }

    }

    /*
    * proof for operator who's ephemeral key has been leaked
    */
    function verifyEphemeralKeyIntegrity(address operator, bytes32 leakedEphemeralKey) external {
        
        if (block.timestamp < EKRegistry[operator].timestamp + UPDATE_PERIOD){
            if (EKRegistry[operator].keyHash == keccak256(abi.encode(leakedEphemeralKey))) {
                IServiceManager serviceManager = repository.serviceManager();
                //trigger slashing function for that datalayr node address
                serviceManager.slashOperator(operator);
            }
        }
    }

    function getLastEKPostTimestamp(address operator) external view returns (uint) {
        return latestEK[operator].timestamp;
    }

}
