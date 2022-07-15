// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IEphemeralKeyRegistry.sol";
import "../interfaces/IBLSRegistry.sol";
import "../permissions/RepositoryAccess.sol";

contract EphemeralKeyRegistry is IEphemeralKeyRegistry, RepositoryAccess {
    struct EKEntry {
        bytes32 keyHash;
        bytes32 emphemeralKey;
        uint192 timestamp;
        uint32 startTaskNumber;
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

    /*
    * Allows operator to post their first ephemeral key hash via BLSRegistry (on registration)
    */
    function postFirstEphemeralKeyHash(address operator, bytes32 EKHash) external onlyRegistry {
        uint32 currentTaskNumber = repository.serviceManager().taskNumber();

        EKEntry memory newEKEntry;
        newEKEntry.keyHash = EKHash;
        newEKEntry.timestamp = uint192(block.timestamp);
        newEKEntry.startTaskNumber = currentTaskNumber;
        EKHistory[operator].push(newEKEntry);
    }

    /*
    * Allows operator to post their final ephemeral key preimage via BLSRegistry (on degregistration)
    */
    function postLastEphemeralKeyPreImage(address operator, bytes32 prevEK) external onlyRegistry {
        uint256 historyLength = EKHistory[operator].length - 1;
        EKEntry memory existingEKEntry = EKHistory[operator][historyLength];

        require(existingEKEntry.keyHash == keccak256(abi.encode(prevEK)), "Ephemeral key does not match previous ephemeral key commitment");

        uint32 currentTaskNumber = repository.serviceManager().taskNumber();

        existingEKEntry.emphemeralKey = prevEK;
        existingEKEntry.endTaskNumber = currentTaskNumber - 1;
        EKHistory[operator][historyLength] = existingEKEntry;        
    }

     /*
    * Allows operator to update their ephemeral key hash and post their previous ephemeral key 
    */
    function updateEphemeralKeyPreImage(bytes32 prevEK, bytes32 newEKHash) external {
        uint256 historyLength = EKHistory[msg.sender].length - 1;
        EKEntry memory existingEKEntry = EKHistory[msg.sender][historyLength];

        require(existingEKEntry.keyHash == keccak256(abi.encode(prevEK)), "Ephemeral key does not match previous ephemeral key commitment");

        require(block.timestamp >= existingEKEntry.timestamp + UPDATE_PERIOD, "key update cannot be completed too early");
        require(block.timestamp <= existingEKEntry.timestamp + UPDATE_PERIOD + REVEAL_PERIOD, "key update cannot be completed as update window has expired");

        uint32 currentTaskNumber = repository.serviceManager().taskNumber();

        existingEKEntry.emphemeralKey = prevEK;
        existingEKEntry.endTaskNumber = currentTaskNumber - 1;
        EKHistory[msg.sender][historyLength] = existingEKEntry;        

        EKEntry memory newEKEntry;
        newEKEntry.keyHash = newEKHash;
        newEKEntry.timestamp = uint192(block.timestamp);
        newEKEntry.startTaskNumber = currentTaskNumber;
        EKHistory[msg.sender].push(newEKEntry);
    }

    /*
    * retrieve a operator's current EK hash
    */
    function getCurrEphemeralKeyHash(address operator) external view returns (bytes32){
        uint256 historyLength = EKHistory[operator].length - 1;
        return EKHistory[operator][historyLength].keyHash;
    }

    function getLatestEphemeralKey(address operator)
        external view
        returns (bytes32)
    {
        uint256 historyLength = EKHistory[operator].length - 1;
        if (EKHistory[operator][historyLength].emphemeralKey != bytes32(0)) {
            return EKHistory[operator][historyLength].emphemeralKey;
        } else {
            return EKHistory[operator][historyLength - 1].emphemeralKey;
        }
    }

    function getEphemeralKeyForTaskNumber(address operator, uint32 taskNumber)
        external view
        returns (bytes32)
    {
        uint256 historyLength = EKHistory[operator].length - 1;
        EKEntry memory existingEKEntry = EKHistory[operator][historyLength];

        if (existingEKEntry.startTaskNumber >= taskNumber) {
            revert("taskNumber corresponds to latest EK which is still unrevealed");
        } else {
            for (; historyLength > 0; --historyLength) {
                if (
                    (taskNumber >= EKHistory[msg.sender][historyLength].startTaskNumber)
                    &&
                    (taskNumber <= EKHistory[msg.sender][historyLength].endTaskNumber)
                ) {
                    return EKHistory[msg.sender][historyLength].emphemeralKey;
                }
            } 
        }
        revert("did not find EK");
    }   

    /*
    *proof for operator that hasn't updated their ephemeral key within the update window.  
    */
    function proveStaleEphemeralKey(address operator) external {
        uint256 historyLength = EKHistory[operator].length - 1;
        EKEntry memory existingEKEntry = EKHistory[operator][historyLength];

        IBLSRegistry registry = IBLSRegistry(address(repository.registry()));

        //check if operator is still active in the DLRegistry
        require(registry.getOperatorStatus(operator) == 1, "operator not active");

        if((block.timestamp > existingEKEntry.timestamp + UPDATE_PERIOD + REVEAL_PERIOD)) {
            IServiceManager serviceManager = repository.serviceManager();
            //trigger slashing for operator who hasn't updated their EK
            serviceManager.slashOperator(operator);
        }

    }

    /*
    * proof for operator who's ephemeral key has been leaked
    */
    function verifyEphemeralKeyIntegrity(address operator, bytes32 leakedEphemeralKey) external {
        uint256 historyLength = EKHistory[operator].length - 1;
        EKEntry memory existingEKEntry = EKHistory[operator][historyLength];

        if (block.timestamp < existingEKEntry.timestamp + UPDATE_PERIOD){
            if (existingEKEntry.keyHash == keccak256(abi.encode(leakedEphemeralKey))) {
                IServiceManager serviceManager = repository.serviceManager();
                //trigger slashing function for that datalayr node address
                serviceManager.slashOperator(operator);
            }
        }
    }

    function getLastEKPostTimestamp(address operator) external view returns (uint192) {
        uint256 historyLength = EKHistory[operator].length - 1;
        EKEntry memory existingEKEntry = EKHistory[operator][historyLength];
        return existingEKEntry.timestamp;
    }

}
