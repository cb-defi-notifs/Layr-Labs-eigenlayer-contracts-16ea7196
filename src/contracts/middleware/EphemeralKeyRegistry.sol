// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IEphemeralKeyRegistry.sol";
import "../interfaces/IQuorumRegistry.sol";
import "../permissions/RepositoryAccess.sol";

import "forge-std/Test.sol";

/**
 * @title Registry of Ephemeral Keys for operators, designed for use with Proofs of Custody.
 * @author Layr Labs, Inc.
 * @notice This contract has the functionality for ---
 * (1) storing revealed ephemeral keys for each operator from past,
 * (2) checking if ephemeral keys revealed too early and then slashing if needed,
 * (3) recording when a previous ephemeral key is made inactive
 * @notice See the Dankrad's excellent article for an intro to Proofs of Custody:
 * https://dankradfeist.de/ethereum/2021/09/30/proofs-of-custody.html.
 */
contract EphemeralKeyRegistry is IEphemeralKeyRegistry, RepositoryAccess, DSTest {
    // DATA STRUCTURES
    struct EphemeralKeyEntry {
        // the hash of the ephemeral key
        bytes32 ephemeralKeyHash;
        // when the ephemeral key started being used
        uint32 startTime;
        // when the ephemeral key was revealed
        uint32 revealTime;
    }

    struct EphemeralKeyStartTime {
        uint32 index; 
        uint32 startTime;
    }

    // max amount of time that an operator can use an ephemeral key
    uint32 public constant USAGE_PERIOD = 90 days;
    // max amout of time operator has to submit and confirm the ephemeral key reveal transaction
    uint32 public constant REVEAL_PERIOD = 7 days;
    // operator => index of the ephemeral key to reveal next
    mapping(address => EphemeralKeyStartTime[]) public ephemeralKeyStartTimes;
    // operator => log of ephemeral keys hashes, timestamp at which they were posted, and start/end taskNumbers
    mapping(address => EphemeralKeyEntry[]) public ephemeralKeyEntries;

    // solhint-disable-next-line no-empty-blocks
    constructor(IRepository _repository) RepositoryAccess(_repository) {}

    /**
     * @notice Used by operator to post their first ephemeral key hash via BLSRegistry (on registration).
     * This effectively serves as a commitment to the ephemeral key - when it is revealed during the disclosure period, it can be verified against the hash.
     * @param operator for signing on bomb-based queries
     * @param ephemeralKeyHash1 is the hash of the first ephemeral key to be used by `operator`
     * @param ephemeralKeyHash2 is the hash of the second ephemeral key to be used by `operator`
     */
    function postFirstEphemeralKeyHashes(address operator, bytes32 ephemeralKeyHash1, bytes32 ephemeralKeyHash2) external onlyRegistry {
        // record the new ephemeral key entry
        ephemeralKeyEntries[operator].push(
            EphemeralKeyEntry({
                ephemeralKeyHash: ephemeralKeyHash1,
                startTime: uint32(block.timestamp),
                revealTime: 0
            })
        );
        // record the next ephemeral key, starting usage after USAGE_PERIOD
        ephemeralKeyEntries[operator].push(
            EphemeralKeyEntry({
                ephemeralKeyHash: ephemeralKeyHash2,
                startTime: uint32(block.timestamp) + USAGE_PERIOD,
                revealTime: 0
            })
        );
    }
                               
    /**
     * @notice Used by the operator to commit to a new ephemeral key and invalidate the current one
     * @param ephemeralKeyHash is being committed
     */
    function commitNewEphemeralKeyHash(bytes32 ephemeralKeyHash) external {
        // get the number of entries for the operator
        uint256 entriesLength = ephemeralKeyEntries[msg.sender].length;

        if(ephemeralKeyEntries[msg.sender][entriesLength - 1].startTime < uint32(block.timestamp)) {
            // if the last ephemeral key is the active one, 
            // add the ephemeral key entry and make it the current active one
            ephemeralKeyEntries[msg.sender].push(
                EphemeralKeyEntry({
                    ephemeralKeyHash: ephemeralKeyHash,
                    startTime: uint32(block.timestamp),
                    revealTime: 0
                })
            );
        } else if(ephemeralKeyEntries[msg.sender][entriesLength - 2].startTime < uint32(block.timestamp)) {
            // if the 2nd to last ephemeral key is the active one, 
            // make the last ephemeral key the current active one,
            // and add the ephemeral key entry

            ephemeralKeyEntries[msg.sender][entriesLength - 1].startTime = uint32(block.timestamp);

            ephemeralKeyEntries[msg.sender].push(
                EphemeralKeyEntry({
                    ephemeralKeyHash: ephemeralKeyHash,
                    startTime: uint32(block.timestamp) + USAGE_PERIOD,
                    revealTime: 0
                })
            );
        } else {
            //this is an invalid state for the contract to be in?
            revert("EphemeralKeyRegistry.commitNewEphemeralKeyHash: invalid state");
        }
    }

    /**
     * @notice Used by the operator to reveal an ephemeral key
     * @param index is the index of the ephemeral key to reveal
     * @param prevEpheremeralKey is the previous ephemeral key
     */
    function revealEphemeralKey(uint256 index, bytes32 prevEpheremeralKey) external {
        _revealEphemeralKey(msg.sender, index, prevEpheremeralKey);
    }

    /**
     * @notice Used by the operator to reveal their unrevealed ephemeral keys
     * @param indexes are the indexes of the ephemeral keys to reveal
     * @param prevEpheremeralKeys are the previous ephemeral keys
     */
    function revealLastEphemeralKeys(address operator, uint256[] memory indexes, bytes32[] memory prevEpheremeralKeys) external onlyRegistry {
        for(uint i = 0; i < indexes.length; i++) {
            _revealEphemeralKey(operator, indexes[i], prevEpheremeralKeys[i]);
        }
    }

    /**
     * @notice Used by watchers to prove that an operator hasn't reveald an ephemeral key
     * @param operator is the entity with the stale unrevealed ephemeral key
     * @param index is the index of the stale entry
     */
    function verifyStaleEphemeralKey(address operator, uint256 index) external {
        require(ephemeralKeyEntries[operator][index].revealTime == 0, "EphemeralKeyRegistry.verifyStaleEphemeralKey: ephemeral key has been revealed");
        if(index == ephemeralKeyEntries[operator].length){
            //if the last ephemeral key is stale, it must be used for more than USAGE_PERIOD
            require(ephemeralKeyEntries[operator][index].startTime + USAGE_PERIOD < uint32(block.timestamp), 
                "EphemeralKeyRegistry.verifyStaleEphemeralKey: ephemeral key has not been used for USAGE_PERIOD yet");
        } else {
            //otherwise, the next ephemeral key must have been active for more than REVEAL_PERIOD
            require(ephemeralKeyEntries[operator][index+1].startTime + REVEAL_PERIOD < uint32(block.timestamp), 
                "EphemeralKeyRegistry.verifyStaleEphemeralKey: ephemeral key has not been used for REVEAL_PERIOD yet");
        }

        //freeze operator with stale ephemeral key
        IServiceManager serviceManager = repository.serviceManager();
        serviceManager.freezeOperator(operator);
    }

    /**
     * @notice Used by watchers to prove that an operator has shared their epheemeral key with other entities
     * @param operator is the entity that shared their ephemeral key
     * @param index is the index of the ephemeral key they shared
     * @param ephemeralKey is the preimage of the stored ephemeral key hash
     */
    function verifyLeakedEphemeralKey(address operator, uint256 index, bytes32 ephemeralKey) external {
         // verify that the operator is active
        IQuorumRegistry registry = IQuorumRegistry(address(_registry()));
        require(
            registry.isActiveOperator(operator),
            "EphemeralKeyRegistry.verifyLeakedEphemeralKey: operator is not active"
        );

        require(
            ephemeralKeyEntries[operator][index].ephemeralKeyHash == keccak256(abi.encodePacked(ephemeralKey)),
            "EphemeralKeyRegistry.verifyLeakedEphemeralKey: Ephemeral key does not match previous ephemeral key commitment"
        );
        
        require(ephemeralKeyEntries[operator][index].revealTime == 0, "EphemeralKeyRegistry.verifyLeakedEphemeralKey: ephemeral key has been revealed");
        if(index != ephemeralKeyEntries[operator].length){
            //if the last ephemeral key is being leaked, then make sure it's not in its reveal period

            //the time at which the leaked key stopped being active was then the one after it started being active
            uint256 endTime = ephemeralKeyEntries[msg.sender][index+1].startTime;
            require(
                block.timestamp < endTime ||
                block.timestamp > endTime + REVEAL_PERIOD,
                "EphemeralKeyRegistry.verifyLeakedEphemeralKey: key cannot be leaked within reveal period"
            );
        }

        //freeze operator with stale ephemeral key
        IServiceManager serviceManager = repository.serviceManager();
        serviceManager.freezeOperator(operator);
    }

    function getEphemeralKeyAtTime(address operator, uint256 index, uint32 timestamp) external view returns(bytes32) {
        require(ephemeralKeyEntries[operator][index].startTime <= timestamp && // the ephemeral key was in use before `timestamp`
                (
                    ephemeralKeyEntries[operator].length - 1 == index || // it is the last entry 
                    ephemeralKeyEntries[operator][index+1].startTime > timestamp // or the next entry started after the timestamp
                ),
                "EphemeralKeyRegistry.getEphemeralKeyAtTime: index is not the correct entry index"
        );
        return ephemeralKeyEntries[operator][index].ephemeralKeyHash;
    }

    function _revealEphemeralKey(address operator, uint256 index, bytes32 prevEpheremeralKey) internal {
        // verify that the operator is active
        IQuorumRegistry registry = IQuorumRegistry(address(_registry()));
        require(
            registry.isActiveOperator(operator),
            "EphemeralKeyRegistry.revealEphemeralKey: operator is not active"
        );

        require(
            ephemeralKeyEntries[operator][index].ephemeralKeyHash == keccak256(abi.encodePacked(prevEpheremeralKey)),
            "EphemeralKeyRegistry.revealEphemeralKey: Ephemeral key does not match previous ephemeral key commitment"
        );

        //the time at which the revealed key stopped being active was then the one after it started being active
        uint256 endTime = ephemeralKeyEntries[operator][index+1].startTime;

        // checking the validity period of the ephemeral key update
        require(
            block.timestamp > endTime,
            "EphemeralKeyRegistry.revealEphemeralKey: key update cannot be completed too early"
        );
        require(
            block.timestamp < endTime + REVEAL_PERIOD,
            "EphemeralKeyRegistry.revealEphemeralKey: key update cannot be completed too late"
        );

        // updating the previous EK entry
        ephemeralKeyEntries[operator][index].revealTime = uint32(block.timestamp);
    }
}
