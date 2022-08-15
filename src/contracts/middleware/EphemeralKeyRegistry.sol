// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IEphemeralKeyRegistry.sol";
import "../interfaces/IQuorumRegistry.sol";
import "../permissions/RepositoryAccess.sol";

/**
 @notice This contract has the functionality for ---
            (1) storing revealed ephemeral keys for each operator from past,
            (2) checking if ephemeral keys revealed too early and then slashing if needed,
            (3) recording when a previous ephemeral key is made inactive
 */


contract EphemeralKeyRegistry is IEphemeralKeyRegistry, RepositoryAccess {
    
    /******************
     Data structures    
     ******************/
    struct EKEntry {
        bytes32 keyHash;
        bytes32 ephemeralKey;

        // timestamp when the keyhash is first recorded
        uint192 timestamp;

        // task number of the middleware from which ephemeral key is being used
        uint32 startTaskNumber;

        // task number of the middleware  until which ephemeral key is being used
        uint32 endTaskNumber;
    }

    // max amount of time that an operator can take to update their ephemeral key
    uint256 public constant UPDATE_PERIOD = 18 days;

    //max amout of time operator has to submit and confirm the ephemeral key reveal transaction
    uint256 public constant REVEAL_PERIOD = 3 days;

    // operator => history of ephemeral keys, hashes of them, timestamp at which they were posted, and start/end taskNumbers
    mapping(address => EKEntry[]) public EKHistory;

    constructor(IRepository _repository)
        RepositoryAccess(_repository)
    {
    }

    /**
     @notice Used by operator to post their first ephemeral key hash via BLSRegistry (on registration)
     */
    /** 
     @param EKHash is the hash of the Ephemeral key that is being currently used by the 
     @param operator for signing on bomb-based queries.
     */ 
    function postFirstEphemeralKeyHash(address operator, bytes32 EKHash) external onlyRegistry {
        uint32 currentTaskNumber = repository.serviceManager().taskNumber();

        EKEntry memory newEKEntry;
        newEKEntry.keyHash = EKHash;
        newEKEntry.timestamp = uint192(block.timestamp);
        newEKEntry.startTaskNumber = currentTaskNumber;

        // record the new EK entry 
        EKHistory[operator].push(newEKEntry);
    }

    /**
     @notice Used by the operator to post their ephemeral key preimage via BLSRegistry 
             (on degregistration) after the expiry of its usage. This function is called only
             when operator is going to de-register from the middleware.  Check its usage in 
             deregisterOperator  in BLSRegistryWithBomb.sol
     */
    /**
     @param prevEK is the preimage. 
     */ 
    function postLastEphemeralKeyPreImage(address operator, bytes32 prevEK) external onlyRegistry {
        uint256 historyLength = EKHistory[operator].length - 1;

        // retrieve the most recent EK entry for the operator
        EKEntry memory existingEKEntry = EKHistory[operator][historyLength];

        // check that the preimage matches with the hash
        require(existingEKEntry.keyHash == keccak256(abi.encode(prevEK)), "EphemeralKeyRegistry.postLastEphemeralKeyPreImage: Ephemeral key does not match previous ephemeral key commitment");

        uint32 currentTaskNumber = repository.serviceManager().taskNumber();

        // update the EK entry
        existingEKEntry.ephemeralKey = prevEK;
        existingEKEntry.endTaskNumber = currentTaskNumber - 1;
        EKHistory[operator][historyLength] = existingEKEntry;        
    }



    /**
     @notice Used by the operator to update their ephemeral key hash and post their 
             previous ephemeral key (on degregistration) after the expiry of its usage.  
             Revealing of current ephemeral key and describing the hash of the new ephemeral
             key done together.
     */
    /**
     @param prevEK is the previous ephemeral key,
     @param newEKHash is the hash of the new ephemeral key.
     */ 
    function updateEphemeralKeyPreImage(bytes32 prevEK, bytes32 newEKHash) external {
        uint256 historyLength = EKHistory[msg.sender].length - 1;
        EKEntry memory existingEKEntry = EKHistory[msg.sender][historyLength];

        require(existingEKEntry.keyHash == keccak256(abi.encode(prevEK)), "EphemeralKeyRegistry.updateEphemeralKeyPreImage: Ephemeral key does not match previous ephemeral key commitment");

        // checking the validity period of the ephemeral key update
        require(
            block.timestamp >= existingEKEntry.timestamp + UPDATE_PERIOD,
            "EphemeralKeyRegistry.updateEphemeralKeyPreImage: key update cannot be completed too early"
        );
        require(
            block.timestamp <= existingEKEntry.timestamp + UPDATE_PERIOD + REVEAL_PERIOD,
            "EphemeralKeyRegistry.updateEphemeralKeyPreImage: key update cannot be completed as update window has expired"
        );

        uint32 currentTaskNumber = repository.serviceManager().taskNumber();

        // updating the previous EK entry
        existingEKEntry.ephemeralKey = prevEK;
        existingEKEntry.endTaskNumber = currentTaskNumber - 1;
        EKHistory[msg.sender][historyLength] = existingEKEntry;        

        // new EK entry
        EKEntry memory newEKEntry;
        newEKEntry.keyHash = newEKHash;
        newEKEntry.timestamp = uint192(block.timestamp);
        newEKEntry.startTaskNumber = currentTaskNumber;
        EKHistory[msg.sender].push(newEKEntry);
    }



    /**
     @notice retrieve the operator's current EK hash
     */
    // CRITIC ---  getLatestEphemeralKey seems to be superior than getCurrEphemeralKeyHash
    function getCurrEphemeralKeyHash(address operator) external view returns (bytes32){
        uint256 historyLength = EKHistory[operator].length - 1;
        return EKHistory[operator][historyLength].keyHash;
    }

    /**
     @notice retrieve the operator's current EK hash
     */
    function getLatestEphemeralKey(address operator)
        external view
        returns (bytes32)
    {
        uint256 historyLength = EKHistory[operator].length - 1;
        if (EKHistory[operator][historyLength].ephemeralKey != bytes32(0)) {
            return EKHistory[operator][historyLength].ephemeralKey;
        } else {
            // recent EKEntry is still within UPDATE_PERIOD
            return EKHistory[operator][historyLength - 1].ephemeralKey;
        }
    }


    /**
     @notice This function is used for getting the ephemeral key pertaining to a particular taskNumber
     */
    function getEphemeralKeyForTaskNumber(address operator, uint32 taskNumber)
        external view
        returns (bytes32)
    {
        uint256 historyLength = EKHistory[operator].length - 1;
        EKEntry memory existingEKEntry = EKHistory[operator][historyLength];

        if (existingEKEntry.startTaskNumber >= taskNumber) {
            revert("EphemeralKeyRegistry.getEphemeralKeyForTaskNumber: taskNumber corresponds to latest EK which is still unrevealed");
        } else {
            for (; historyLength > 0; --historyLength) {
                if (
                    (taskNumber >= EKHistory[msg.sender][historyLength].startTaskNumber)
                    &&
                    (taskNumber <= EKHistory[msg.sender][historyLength].endTaskNumber)
                ) {
                    return EKHistory[msg.sender][historyLength].ephemeralKey;
                }
            } 
        }
        revert("EphemeralKeyRegistry.getEphemeralKeyForTaskNumber: did not find EK");
    }   


    /** 
     @notice proof for operator that hasn't updated their ephemeral key within the update window.  
    */
    function proveStaleEphemeralKey(address operator) external {
        // get the info on latest EK 
        uint256 historyLength = EKHistory[operator].length - 1;
        EKEntry memory existingEKEntry = EKHistory[operator][historyLength];

        IQuorumRegistry registry = IQuorumRegistry(address(repository.registry()));

        //check if operator is still active in the DLRegistry
        require(
            registry.getOperatorStatus(operator) == IQuorumRegistry.Active.ACTIVE,
            "EphemeralKeyRegistry.proveStaleEphemeralKey: operator not active"
        );

        if((block.timestamp > existingEKEntry.timestamp + UPDATE_PERIOD + REVEAL_PERIOD)) {
            IServiceManager serviceManager = repository.serviceManager();
            //trigger slashing for operator who hasn't updated their EK
            serviceManager.freezeOperator(operator);
        }

    }


    /**
     @notice Used for proving that leaked key is actually the ephemeral key 
             that was supposed to be not revealed   
    */
    function verifyEphemeralKeyIntegrity(address operator, bytes32 leakedEphemeralKey) external {
        uint256 historyLength = EKHistory[operator].length - 1;
        EKEntry memory existingEKEntry = EKHistory[operator][historyLength];

        if (block.timestamp < existingEKEntry.timestamp + UPDATE_PERIOD){
            if (existingEKEntry.keyHash == keccak256(abi.encode(leakedEphemeralKey))) {
                IServiceManager serviceManager = repository.serviceManager();
                //trigger slashing function for that datalayr node address
                serviceManager.freezeOperator(operator);
            }
        }
    }

    function getLastEKPostTimestamp(address operator) external view returns (uint192) {
        uint256 historyLength = EKHistory[operator].length - 1;
        EKEntry memory existingEKEntry = EKHistory[operator][historyLength];
        return existingEKEntry.timestamp;
    }

}
