// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IEphemeralKeyRegistry.sol";
import "../interfaces/IQuorumRegistry.sol";
import "../interfaces/IServiceManager.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

// import "forge-std/Test.sol";

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
contract EphemeralKeyRegistry is Initializable, IEphemeralKeyRegistry {

    // max amount of blocks that an operator can use an ephemeral key
    uint32 public constant USAGE_PERIOD_BLOCKS = 648000; //90 days at 12s/block
 
    // max amout of blocks operator has to submit and confirm the ephemeral key reveal transaction
    uint32 public constant REVEAL_PERIOD_BLOCKS = 50400; //7 days at 12s/block

    /// @notice The Registry contract for this middleware, where operators register and deregister.
    IQuorumRegistry public immutable registry;

    /// @notice The ServiceManager contract for this middleware, where tasks are created / initiated.
    IServiceManager public immutable serviceManager;

    // operator => list of ephemeral key hashes, block at which they started being used and were revealed
    mapping(address => EphemeralKeyEntry[]) public ephemeralKeyEntries;

    event EphemeralKeyRevealed(uint256 index, bytes32 ephemeralKey);
    event EphemeralKeyCommitted(uint256 index);
    event EphemeralKeyLeaked(uint256 index, bytes32 ephemeralKey);
    event EphemeralKeyProvenStale(uint256 index);

    /// @notice when applied to a function, ensures that the function is only callable by the `registry`
    modifier onlyRegistry() {
        require(msg.sender == address(registry), "onlyRegistry");
        _;
    }

    constructor(IQuorumRegistry _registry, IServiceManager _serviceManager) {
        registry = _registry;
        serviceManager = _serviceManager;
    }

    /**
     * @notice Used by operator to post their first ephemeral key hashes via BLSRegistry (on registration).
     *         During revealing, the posted ephemeral keys will be checked against the ones committed on chain.
     * @param operator for signing on bomb-based queries
     * @param ephemeralKeyHash1 is the hash of the first ephemeral key to be used by `operator`
     * @param ephemeralKeyHash2 is the hash of the second ephemeral key to be used by `operator`
     * @dev This function can only be called by the registry itself.
     */
    function postFirstEphemeralKeyHashes(address operator, bytes32 ephemeralKeyHash1, bytes32 ephemeralKeyHash2) external onlyRegistry {
        // record the new ephemeral key entry
        ephemeralKeyEntries[operator].push(
            EphemeralKeyEntry({
                ephemeralKeyHash: ephemeralKeyHash1,
                startBlock: uint32(block.number),
                // set the revealBLock to 0 because it has not been revealed
                revealBlock: 0
            })
        );
        // record the next ephemeral key, starting usage after USAGE_PERIOD_BLOCKS
        ephemeralKeyEntries[operator].push(
            EphemeralKeyEntry({
                ephemeralKeyHash: ephemeralKeyHash2,
                startBlock: uint32(block.number) + USAGE_PERIOD_BLOCKS,
                // set the revealBLock to 0 because it has not been revealed
                revealBlock: 0
            })
        );
    }
                               
    /**
     * @notice Used by the operator to commit to a new ephemeral key(s) and invalidate the current one.
     *         This would be called whenever 
     *              (1) an operator is going to run out of ephemeral keys and needs to put more on chain
     *              (2) an operator wants to reveal all ephemeral keys used before a certain block number
     *                  to propagate stake updates
     * @param ephemeralKeyHashes are the new ephemeralKeyHash(es) being committed
     * @param activeKeyIndex is the index of the caller's active ephemeral key
     */
    function commitNewEphemeralKeyHashesAndInvalidateActiveKey(bytes32[] calldata ephemeralKeyHashes, uint256 activeKeyIndex) external {
        // get the number of entries for the operator
        uint256 ephemeralKeyEntriesLength = ephemeralKeyEntries[msg.sender].length;

        // verify that the specified key -- indicated by the `activeKeyIndex` input -- is active
        require(
            // check that the `activeKeyIndex`th key became active before the present
            ephemeralKeyEntries[msg.sender][activeKeyIndex].startBlock < uint32(block.number)
            && 
                (
                    // either the `activeKeyIndex`th key is the last one in the list, or the next key in the list hasn't started being active yet
                    activeKeyIndex + 1 == ephemeralKeyEntriesLength ||
                    ephemeralKeyEntries[msg.sender][activeKeyIndex + 1].startBlock >= uint32(block.number)
                ),
            "EphemeralKeyRegistry.commitNewEphemeralKeyHashesAndInvalidateActiveKey: activeKeyIndex does not specify active ephemeral key"
        );

        /**
         * Next we add the ephemeral key entry(s) and make the key after `activeKeyIndex` active, starting in the next block.
         * There are several different cases for this step, outlined below in the if-else logic.
         */
        // 1) if the last ephemeral key is the active one
        if (activeKeyIndex + 1 == ephemeralKeyEntriesLength) {
            // we need to push a new entry to the operator's list of ephemeral keys and make it active in the next block
            ephemeralKeyEntries[msg.sender].push(
                EphemeralKeyEntry({
                    ephemeralKeyHash: ephemeralKeyHashes[0],
                    // new key will become active in the next block
                    startBlock: uint32(block.number) + 1,
                    // set the revealBLock to 0 because it has not been revealed
                    revealBlock: 0
                })
            );      
        // 2) if there is already at least one other ephemeral key 'waiting to become active' in the operator's list of ephemeral keys
        } else {
            // make the key after the active one become active in the next block
            ephemeralKeyEntries[msg.sender][activeKeyIndex + 1].startBlock = uint32(block.number) + 1;

            // iterate through any intermediate entries in the operator's list of ephemeral keys and update their startBlock values appropriately
            for (uint256 i = activeKeyIndex + 2; i < ephemeralKeyEntriesLength;) {
                ephemeralKeyEntries[msg.sender][i].startBlock = ephemeralKeyEntries[msg.sender][i - 1].startBlock + USAGE_PERIOD_BLOCKS;
                unchecked {
                    ++i;
                }
            }

            // push a new entry to the operator's list of ephemeral keys and give it the appropriate startBlock
            ephemeralKeyEntries[msg.sender].push(
                EphemeralKeyEntry({
                    ephemeralKeyHash: ephemeralKeyHashes[0],
                    // set the startBlock to be `USAGE_PERIOD_BLOCKS` after the previous key's startBlock
                    startBlock: ephemeralKeyEntries[msg.sender][ephemeralKeyEntriesLength - 1].startBlock + USAGE_PERIOD_BLOCKS,
                    // set the revealBLock to 0 because it has not been revealed
                    revealBlock: 0
                })
            );
        }

        // push any additional new ephemeral key hashes. `i` starts at 1 here since since we've already pushed one new ephemeral key hash.
        uint256 ephemeralKeyHashesLength = ephemeralKeyHashes.length;
        for (uint256 i = 1; i < ephemeralKeyHashesLength; ++i) {
            // push a new entry to the operator's list of ephemeral keys and give it the appropriate startBlock
            ephemeralKeyEntries[msg.sender].push(
                EphemeralKeyEntry({
                    ephemeralKeyHash: ephemeralKeyHashes[i],
                    // set the startBlock to be `USAGE_PERIOD_BLOCKS` after the previous key's startBlock
                    startBlock: ephemeralKeyEntries[msg.sender][ephemeralKeyEntries[msg.sender].length - 1].startBlock + USAGE_PERIOD_BLOCKS,
                    // set the revealBLock to 0 because it has not been revealed
                    revealBlock: 0
                })
            );
        }

        // emit event for new committed ephemeral key
        emit EphemeralKeyCommitted(ephemeralKeyEntries[msg.sender].length);
    }

    /**
     * @notice Used by the operator to reveal an ephemeral key
     * @param index is the index of the ephemeral key to reveal
     * @param prevEphemeralKey is the previous ephemeral key
     * @dev This function should only be called when the key is already inactive and during the key's reveal period. Otherwise, the operator
     * can be slashed through a call to `verifyLeakedEphemeralKey`.
     */
    function revealEphemeralKey(uint256 index, bytes32 prevEphemeralKey) external {
        if (index != 0) {
            require(ephemeralKeyEntries[msg.sender][index - 1].revealBlock != 0, "EphemeralKeyRegistry.revealEphemeralKey: must reveal keys in order");
        }
        require(index + 1 < ephemeralKeyEntries[msg.sender].length, 
            "EphemeralKeyRegistry.revealEphemeralKey: cannot reveal last key outside of calling revealLastEphemeralKeys");
        _revealEphemeralKey(msg.sender, index, prevEphemeralKey);
    }

    /**
     * @notice Used by the operator to reveal their unrevealed ephemeral keys via BLSRegistry (on deregistration).
     * @param startIndex is the index of the ephemeral key to reveal
     * @param prevEphemeralKeys are the previous ephemeral keys
     * @dev This function can only be called by the registry itself.
     */
    function revealLastEphemeralKeys(address operator, uint256 startIndex, bytes32[] memory prevEphemeralKeys) external onlyRegistry {
        if (startIndex != 0) {
            require(ephemeralKeyEntries[operator][startIndex - 1].revealBlock != 0, "EphemeralKeyRegistry.revealLastEphemeralKeys: must reveal keys in order");
        }
        // get the final index plus one
        uint256 finalIndexPlusOne = startIndex + prevEphemeralKeys.length;
        for (uint256 i = startIndex; i < finalIndexPlusOne;) {
            require(
                ephemeralKeyEntries[operator][i].ephemeralKeyHash == keccak256(abi.encodePacked(prevEphemeralKeys[i-startIndex])),
                "EphemeralKeyRegistry.revealLastEphemeralKeys: Ephemeral key does not match previous ephemeral key commitment"
            );
            ephemeralKeyEntries[operator][i].revealBlock = uint32(block.number);
            //emit event for indexing
            emit EphemeralKeyRevealed(i, prevEphemeralKeys[i]);
            unchecked {
                ++i;
            }
        }
        require(ephemeralKeyEntries[operator].length == finalIndexPlusOne,
            "EphemeralKeyRegistry.revealLastEphemeralKeys: all ephemeral keys must be revealed");
    }

    /**
     * @notice Used by watchers to prove that an operator hasn't revealed an ephemeral key when they should have.
     * @param operator is the entity with the stale unrevealed ephemeral key
     * @param index is the index of the stale entry
     */
    function verifyStaleEphemeralKey(address operator, uint256 index) external {
        require(ephemeralKeyEntries[operator][index].revealBlock == 0, "EphemeralKeyRegistry.verifyStaleEphemeralKey: ephemeral key has been revealed");
        if (index + 1 == ephemeralKeyEntries[operator].length){
            // for the last ephemeral key to be stale, it must have been used for strictly more than USAGE_PERIOD_BLOCKS
            require(ephemeralKeyEntries[operator][index].startBlock + USAGE_PERIOD_BLOCKS < uint32(block.number), 
                "EphemeralKeyRegistry.verifyStaleEphemeralKey: ephemeral key has not been used for USAGE_PERIOD_BLOCKS yet");
        } else {
            // otherwise, for an ephemeral key to be stale, the next ephemeral key must have been active for strictly more than REVEAL_PERIOD_BLOCKS
            require(ephemeralKeyEntries[operator][index + 1].startBlock + REVEAL_PERIOD_BLOCKS < uint32(block.number), 
                "EphemeralKeyRegistry.verifyStaleEphemeralKey: ephemeral key has not been used for REVEAL_PERIOD_BLOCKS yet");
        }

        // emit event for stale ephemeral key
        emit EphemeralKeyProvenStale(index);

        // freeze operator with stale ephemeral key
        serviceManager.freezeOperator(operator);
    }

    /**
     * @notice Used by watchers to prove that an operator has inappropriately shared their ephemeral key with other entities.
     * @param operator is the entity that shared their ephemeral key
     * @param index is the index of the ephemeral key they shared
     * @param ephemeralKey is the preimage of the stored ephemeral key hash
     */
    function verifyLeakedEphemeralKey(address operator, uint256 index, bytes32 ephemeralKey) external {
         // verify that the operator is active
        require(
            registry.isActiveOperator(operator),
            "EphemeralKeyRegistry.verifyLeakedEphemeralKey: operator is not active"
        );

        require(
            ephemeralKeyEntries[operator][index].ephemeralKeyHash == keccak256(abi.encodePacked(ephemeralKey)),
            "EphemeralKeyRegistry.verifyLeakedEphemeralKey: Ephemeral key does not match previous ephemeral key commitment"
        );
        
        require(ephemeralKeyEntries[operator][index].revealBlock == 0, "EphemeralKeyRegistry.verifyLeakedEphemeralKey: ephemeral key has been revealed");
        if (index + 1 != ephemeralKeyEntries[operator].length) {
            // if an inactive ephemeral key is being leaked, then make sure it's not in its reveal period

            // the block at which the leaked key stopped being active is the
            // startBlock of the key one entry after the leaked key
            uint256 endBlock = ephemeralKeyEntries[operator][index+1].startBlock;
            require(
                block.number < endBlock ||
                block.number > endBlock + REVEAL_PERIOD_BLOCKS,
                "EphemeralKeyRegistry.verifyLeakedEphemeralKey: key cannot be leaked within reveal period"
            );
        }

        //emit event for leaked ephemeral key
        emit EphemeralKeyLeaked(index, ephemeralKey);

        //freeze operator with stale ephemeral key
        serviceManager.freezeOperator(operator);
    }

    /**
     * @notice Returns the ephemeral key entry of the specified operator at the given blockNumber
     * @param operator is the entity whose ephemeral key entry is being retrieved
     * @param index is the index of the ephemeral key entry that was active during blockNumber
     * @param blockNumber the block number at which the returned entry's ephemeral key was active
     * @dev Reverts if index points to the incorrect public key. index should be calculated off chain before
     *      calling this method via looping through the array and finding the last entry that has a 
     *      startBlock <= blockNumber
     */
    function getEphemeralKeyEntryAtBlock(address operator, uint256 index, uint32 blockNumber) external view returns(EphemeralKeyEntry memory) {
        // verify that the ephemeral key became active at or before `blockNumber` and...
        require(ephemeralKeyEntries[operator][index].startBlock <= blockNumber &&
                (
                    // either the ephemeral key is the last entry or...
                    ephemeralKeyEntries[operator].length - 1 == index ||
                    // or the next ephemeral key entry became active strictly after the blockNumber
                    ephemeralKeyEntries[operator][index + 1].startBlock > blockNumber
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
        require(
            registry.isActiveOperator(operator),
            "EphemeralKeyRegistry.revealEphemeralKey: operator is not active"
        );
        require(
            ephemeralKeyEntries[operator][index].revealBlock == 0, 
            "EphemeralKeyRegistry.revealEphemeralKey: key has already been revealed"
        );
        require(
            ephemeralKeyEntries[operator][index].ephemeralKeyHash == keccak256(abi.encodePacked(prevEphemeralKey)),
            "EphemeralKeyRegistry.revealEphemeralKey: Ephemeral key does not match previous ephemeral key commitment"
        );

        // the block at which the revealed key stopped being active is the startBlock of the key one entry after the revealed one
        uint256 endBlock = ephemeralKeyEntries[operator][index + 1].startBlock;

        // checking the validity period of the ephemeral key update
        require(
            block.number > endBlock,
            "EphemeralKeyRegistry.revealEphemeralKey: key update cannot be completed too early"
        );
        require(
            block.number <= endBlock + REVEAL_PERIOD_BLOCKS,
            "EphemeralKeyRegistry.revealEphemeralKey: key update cannot be completed too late"
        );

        // updating the previous EK entry
        ephemeralKeyEntries[operator][index].revealBlock = uint32(block.number);

        //emit event for indexing
        emit EphemeralKeyRevealed(index, prevEphemeralKey);
    }
}
