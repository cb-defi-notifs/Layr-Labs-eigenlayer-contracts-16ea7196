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
    // max amount of blocks that an operator can use an ephemeral key
    uint32 public constant USAGE_PERIOD = 648000; //90 days at 12s/block
    // max amout of blocks operator has to submit and confirm the ephemeral key reveal transaction
    uint32 public constant REVEAL_PERIOD = 50400; //7 days at 12s/block
    // operator => log of ephemeral keys hashes, block at which they started being used and were revealed
    mapping(address => EphemeralKeyEntry[]) public ephemeralKeyEntries;

    event EphemeralKeyRevealed(uint256 index, bytes32 ephemeralKey);
    event EphemeralKeyCommitted(uint256 index);
    event EphemeralKeyLeaked(uint256 index, bytes32 ephemeralKey);
    event EphemeralKeyProvenStale(uint256 index);

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
                startBlock: uint32(block.number),
                revealBlock: 0
            })
        );
        // record the next ephemeral key, starting usage after USAGE_PERIOD
        ephemeralKeyEntries[operator].push(
            EphemeralKeyEntry({
                ephemeralKeyHash: ephemeralKeyHash2,
                startBlock: uint32(block.number) + USAGE_PERIOD,
                revealBlock: 0
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

        if(ephemeralKeyEntries[msg.sender][entriesLength - 1].startBlock < uint32(block.number)) {
            // if the last ephemeral key is the active one, 
            // add the ephemeral key entry and make it the current active one
            ephemeralKeyEntries[msg.sender].push(
                EphemeralKeyEntry({
                    ephemeralKeyHash: ephemeralKeyHash,
                    startBlock: uint32(block.number),
                    revealBlock: 0
                })
            );
        } else if(ephemeralKeyEntries[msg.sender][entriesLength - 2].startBlock < uint32(block.number)) {
            // if the 2nd to last ephemeral key is the active one, 
            // make the last ephemeral key the current active one,
            // and add the ephemeral key entry

            ephemeralKeyEntries[msg.sender][entriesLength - 1].startBlock = uint32(block.number);

            ephemeralKeyEntries[msg.sender].push(
                EphemeralKeyEntry({
                    ephemeralKeyHash: ephemeralKeyHash,
                    startBlock: uint32(block.number) + USAGE_PERIOD,
                    revealBlock: 0
                })
            );
        } else {
            //this is an invalid state for the contract to be in?
            revert("EphemeralKeyRegistry.commitNewEphemeralKeyHash: invalid state");
        }
        //emit event for new committed ephemeral key
        emit EphemeralKeyCommitted(entriesLength);
    }

    /**
     * @notice Used by the operator to reveal an ephemeral key
     * @param index is the index of the ephemeral key to reveal
     * @param prevEphemeralKey is the previous ephemeral key
     */
    function revealEphemeralKey(uint256 index, bytes32 prevEphemeralKey) external {
        if(index != 0) {
            require(ephemeralKeyEntries[msg.sender][index-1].revealBlock != 0, "EphemeralKeyRegistry.revealEphemeralKey: must reveal keys in order");
        }
        _revealEphemeralKey(msg.sender, index, prevEphemeralKey);
    }

    /**
     * @notice Used by the operator to reveal their unrevealed ephemeral keys
     * @param startIndex is the index of the ephemeral key to reveal
     * @param prevEphemeralKeys are the previous ephemeral keys
     */
    function revealLastEphemeralKeys(address operator, uint256 startIndex, bytes32[] memory prevEphemeralKeys) external onlyRegistry {
        if(startIndex != 0) {
            require(ephemeralKeyEntries[msg.sender][startIndex-1].revealBlock != 0, "EphemeralKeyRegistry.revealLastEphemeralKeys: must reveal keys in order");
        }
        //get the final index plus one
        uint256 finalIndexPlusOne = startIndex + prevEphemeralKeys.length;
        for(uint i = startIndex; i < finalIndexPlusOne; i++) {
            require(
                ephemeralKeyEntries[operator][i].ephemeralKeyHash == keccak256(abi.encodePacked(prevEphemeralKeys[i-startIndex])),
                "EphemeralKeyRegistry.revealLastEphemeralKeys: Ephemeral key does not match previous ephemeral key commitment"
            );
            ephemeralKeyEntries[operator][i].revealBlock = uint32(block.number);
            //emit event for indexing
            emit EphemeralKeyRevealed(i, prevEphemeralKeys[i]);
        }
        require(ephemeralKeyEntries[operator].length == finalIndexPlusOne,
            "EphemeralKeyRegistry.revealLastEphemeralKeys: all ephemeral keys must be revealed");
    }

    /**
     * @notice Used by watchers to prove that an operator hasn't reveald an ephemeral key
     * @param operator is the entity with the stale unrevealed ephemeral key
     * @param index is the index of the stale entry
     */
    function verifyStaleEphemeralKey(address operator, uint256 index) external {
        require(ephemeralKeyEntries[operator][index].revealBlock == 0, "EphemeralKeyRegistry.verifyStaleEphemeralKey: ephemeral key has been revealed");
        if(index == ephemeralKeyEntries[operator].length){
            //if the last ephemeral key is stale, it must be used for more than USAGE_PERIOD
            require(ephemeralKeyEntries[operator][index].startBlock + USAGE_PERIOD < uint32(block.number), 
                "EphemeralKeyRegistry.verifyStaleEphemeralKey: ephemeral key has not been used for USAGE_PERIOD yet");
        } else {
            //otherwise, the next ephemeral key must have been active for more than REVEAL_PERIOD
            require(ephemeralKeyEntries[operator][index+1].startBlock + REVEAL_PERIOD < uint32(block.number), 
                "EphemeralKeyRegistry.verifyStaleEphemeralKey: ephemeral key has not been used for REVEAL_PERIOD yet");
        }

        //emit event for stale ephemeral key
        emit EphemeralKeyProvenStale(index);

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
        
        require(ephemeralKeyEntries[operator][index].revealBlock == 0, "EphemeralKeyRegistry.verifyLeakedEphemeralKey: ephemeral key has been revealed");
        if(index != ephemeralKeyEntries[operator].length){
            //if the last ephemeral key is being leaked, then make sure it's not in its reveal period

            //the block at which the leaked key stopped being active was then the one after it started being active
            uint256 endBlock = ephemeralKeyEntries[msg.sender][index+1].startBlock;
            require(
                block.number < endBlock ||
                block.number > endBlock + REVEAL_PERIOD,
                "EphemeralKeyRegistry.verifyLeakedEphemeralKey: key cannot be leaked within reveal period"
            );
        }

        //emit event for leaked ephemeral key
        emit EphemeralKeyLeaked(index, ephemeralKey);

        //freeze operator with stale ephemeral key
        IServiceManager serviceManager = repository.serviceManager();
        serviceManager.freezeOperator(operator);
    }

    /**
     * @notice Returns the ephemeral key entry of the specified operator at the given blockNumber
     * @param operator is the entity whose ephemeral key entry is being retrieved
     * @param index is the index of the ephemeral key entry that was active during blockNumber
     * @param blockNumber the block number at which the returned entry's ephemeral key was active
     * @dev Reverts if index points to the incorrect public key
     */
    function getEphemeralKeyEntryAtBlock(address operator, uint256 index, uint32 blockNumber) external view returns(EphemeralKeyEntry memory) {
        require(ephemeralKeyEntries[operator][index].startBlock <= blockNumber && // the ephemeral key was in use before `blockNumber`
                (
                    ephemeralKeyEntries[operator].length - 1 == index || // it is the last entry 
                    ephemeralKeyEntries[operator][index+1].startBlock > blockNumber // or the next entry started after the blockNumber
                ),
                "EphemeralKeyRegistry.getEphemeralKeyEntryAtBlock: index is not the correct entry index"
        );
        return ephemeralKeyEntries[operator][index];
    }

    /**
     * @notice Internal function for doing the proper checks and accounting when revealing ephemeral keys
     * @param operator is the entity revealing their ephemeral key
     * @param index is the index of the ephemeral key operator is revealing
     * @param prevEphemeralKey the ephemeral key
     */
    function _revealEphemeralKey(address operator, uint256 index, bytes32 prevEphemeralKey) internal {
        // verify that the operator is active
        IQuorumRegistry registry = IQuorumRegistry(address(_registry()));
        require(
            registry.isActiveOperator(operator),
            "EphemeralKeyRegistry.revealEphemeralKey: operator is not active"
        );

        require(
            ephemeralKeyEntries[operator][index].ephemeralKeyHash == keccak256(abi.encodePacked(prevEphemeralKey)),
            "EphemeralKeyRegistry.revealEphemeralKey: Ephemeral key does not match previous ephemeral key commitment"
        );

        //the block at which the revealed key stopped being active was then the one after it started being active
        uint256 endBlock = ephemeralKeyEntries[operator][index+1].revealBlock;

        // checking the validity period of the ephemeral key update
        require(
            block.number > endBlock,
            "EphemeralKeyRegistry.revealEphemeralKey: key update cannot be completed too early"
        );
        require(
            block.number < endBlock + REVEAL_PERIOD,
            "EphemeralKeyRegistry.revealEphemeralKey: key update cannot be completed too late"
        );
        require(
            ephemeralKeyEntries[operator][index].revealBlock == 0,
            "EphemeralKeyRegistry.revealEphemeralKey: key has already been revealed"
        );

        // updating the previous EK entry
        ephemeralKeyEntries[operator][index].revealBlock = uint32(block.number);

        //emit event for indexing
        emit EphemeralKeyRevealed(index, prevEphemeralKey);
    }
}
