// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "../interfaces/IEphemeralKeyRegistry.sol";
import "../interfaces/IQuorumRegistry.sol";
import "../permissions/RepositoryAccess.sol";

/**
 * @notice This contract has the functionality for ---
 * (1) storing revealed ephemeral keys for each operator from past,
 * (2) checking if ephemeral keys revealed too early and then slashing if needed,
 * (3) recording when a previous ephemeral key is made inactive
 */

contract EphemeralKeyRegistry is IEphemeralKeyRegistry, RepositoryAccess {
    // Data structures
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

    constructor(IRepository _repository) RepositoryAccess(_repository) {}

    /**
     * @notice Used by operator to post their first ephemeral key hash via BLSRegistry (on registration)
     * @param EKHash is the hash of the Ephemeral key that is being currently used by the
     * @param operator for signing on bomb-based queries.
     
    function postFirstEphemeralKeyHash(address operator, bytes32 EKHash) external onlyRegistry {
        // record the new EK entry
        EKHistory[operator].push(
            EKEntry({
                keyHash: EKHash,
                ephemeralKey: bytes32(0),
                timestamp: uint192(block.timestamp),
                startTaskNumber: repository.serviceManager().taskNumber(),
                endTaskNumber: 0
            })
        );
    }

    /**
     * @notice Used by the operator to post their ephemeral key preimage via BLSRegistry
     * (on degregistration) after the expiry of its usage. This function is called only
     * when operator is going to de-register from the middleware.  Check its usage in
     * deregisterOperator  in BLSRegistryWithBomb.sol
     * @param prevEK is the preimage.
     */
    function postLastEphemeralKeyPreImage(address operator, bytes32 prevEK) external onlyRegistry {
        // retrieve the most recent EK entry for the operator
        uint256 historyLength = _getEKHistoryLength(operator);
        EKEntry memory existingEKEntry = EKHistory[operator][historyLength - 1];

        // check that the preimage matches with the hash
        require(
            existingEKEntry.keyHash == keccak256(abi.encode(prevEK)),
            "EphemeralKeyRegistry.postLastEphemeralKeyPreImage: Ephemeral key does not match previous ephemeral key commitment"
        );

        uint32 currentTaskNumber = repository.serviceManager().taskNumber();

        // update the EK entry
        existingEKEntry.ephemeralKey = prevEK;
        existingEKEntry.endTaskNumber = currentTaskNumber - 1;
        EKHistory[operator][historyLength] = existingEKEntry;
    }

    /**
     * @notice Used by the operator to update their ephemeral key hash and post their
     * previous ephemeral key (on degregistration) after the expiry of its usage.
     * Revealing of current ephemeral key and describing the hash of the new ephemeral
     * key done together.
     * @param prevEK is the previous ephemeral key.
     * @param newEKHash is the hash of the new ephemeral key.
     */
    function updateEphemeralKeyPreImage(bytes32 prevEK, bytes32 newEKHash) external {
        // retrieve the most recent EK entry for the operator
        uint256 historyLength = _getEKHistoryLength(msg.sender);
        EKEntry memory existingEKEntry = EKHistory[msg.sender][historyLength - 1];

        require(
            existingEKEntry.keyHash == keccak256(abi.encode(prevEK)),
            "EphemeralKeyRegistry.updateEphemeralKeyPreImage: Ephemeral key does not match previous ephemeral key commitment"
        );

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
        EKHistory[msg.sender][historyLength - 1] = existingEKEntry;

        // new EK entry
        EKEntry memory newEKEntry;
        newEKEntry.keyHash = newEKHash;
        newEKEntry.timestamp = uint192(block.timestamp);
        newEKEntry.startTaskNumber = currentTaskNumber;
        EKHistory[msg.sender].push(newEKEntry);
    }

    // @notice retrieve the operator's current ephemeral key hash
    function getCurrEphemeralKeyHash(address operator) external view returns (bytes32) {
        uint256 historyLength = _getEKHistoryLength(operator);
        return EKHistory[operator][historyLength - 1].keyHash;
    }

    // @notice retrieve the operator's current ephemeral key itself
    function getLatestEphemeralKey(address operator) external view returns (bytes32) {
        uint256 historyLength = _getEKHistoryLength(operator);
        if (EKHistory[operator][historyLength - 1].ephemeralKey != bytes32(0)) {
            return EKHistory[operator][historyLength - 1].ephemeralKey;
            // recent EKEntry is still within UPDATE_PERIOD
        } else {
            if (historyLength == 1) {
                revert("EphemeralKeyRegistry.getLatestEphemeralKey: no ephemeralKey posted yet");
            } else {
                return EKHistory[operator][historyLength - 2].ephemeralKey;
            }
        }
    }

    /**
     * @notice This function is used for getting the ephemeral key pertaining to a particular taskNumber, for an operator
     * @param operator The operator whose ephemeral key we are interested in.
     * @param taskNumber The taskNumber for which we want to retrieve the operator's ephemeral key
     */
    function getEphemeralKeyForTaskNumber(address operator, uint32 taskNumber) external view returns (bytes32) {
        uint256 historyLength = _getEKHistoryLength(operator);
        unchecked {
            historyLength -= 1;
        }
        EKEntry memory existingEKEntry = EKHistory[operator][historyLength];

        if (existingEKEntry.startTaskNumber >= taskNumber) {
            revert(
                "EphemeralKeyRegistry.getEphemeralKeyForTaskNumber: taskNumber corresponds to latest EK which is still unrevealed"
            );
        } else {
            for (; historyLength > 0; --historyLength) {
                if (
                    (taskNumber >= EKHistory[msg.sender][historyLength].startTaskNumber)
                        && (taskNumber <= EKHistory[msg.sender][historyLength].endTaskNumber)
                ) {
                    return EKHistory[msg.sender][historyLength].ephemeralKey;
                }
            }
        }
        revert("EphemeralKeyRegistry.getEphemeralKeyForTaskNumber: did not find EK");
    }

    /**
     * @notice Used for proving that an operator hasn't updated their ephemeral key within the update window.
     * @param operator The operator with a stale ephemeral key
     */
    function proveStaleEphemeralKey(address operator) external {
        // get the info on latest EK
        uint256 historyLength = _getEKHistoryLength(operator);
        EKEntry memory existingEKEntry = EKHistory[operator][historyLength - 1];

        IQuorumRegistry registry = IQuorumRegistry(address(repository.registry()));

        //check if operator is still active in the DLRegistry
        require(
            registry.getOperatorStatus(operator) == IQuorumRegistry.Active.ACTIVE,
            "EphemeralKeyRegistry.proveStaleEphemeralKey: operator not active"
        );

        if ((block.timestamp > existingEKEntry.timestamp + UPDATE_PERIOD + REVEAL_PERIOD)) {
            IServiceManager serviceManager = repository.serviceManager();
            //trigger slashing for operator who hasn't updated their EK
            serviceManager.freezeOperator(operator);
        }
    }

    /**
     * @notice Used for proving that an operator leaked an ephemeral key that was not supposed to be revealed.
     * @param operator The operator who leaked their ephemeral key.
     * @param leakedEphemeralKey The ephemeral key for the operator, which they were not supposed to reveal.
     */
    function verifyEphemeralKeyIntegrity(address operator, bytes32 leakedEphemeralKey) external {
        uint256 historyLength = _getEKHistoryLength(operator);
        EKEntry memory existingEKEntry = EKHistory[operator][historyLength - 1];

        if (block.timestamp < existingEKEntry.timestamp + UPDATE_PERIOD) {
            if (existingEKEntry.keyHash == keccak256(abi.encode(leakedEphemeralKey))) {
                IServiceManager serviceManager = repository.serviceManager();
                //trigger slashing function for that datalayr node address
                serviceManager.freezeOperator(operator);
            }
        }
    }

    // @notice Returns the UTC timestamp at which the operator last renewed their ephemeral key
    function getLastEKPostTimestamp(address operator) external view returns (uint192) {
        uint256 historyLength = _getEKHistoryLength(operator);
        EKEntry memory existingEKEntry = EKHistory[operator][historyLength - 1];
        return existingEKEntry.timestamp;
    }

    function _getEKHistoryLength(address operator) internal view returns (uint256) {
        uint256 historyLength = EKHistory[operator].length;
        if (historyLength == 0) {
            revert("EphemeralKeyRegistry._getEKHistoryLength: historyLength == 0");
        }
        return historyLength;
    }
}
