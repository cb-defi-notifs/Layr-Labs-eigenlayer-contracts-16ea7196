// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/**
 * @title Interface for an Ephemeral Key Registry, designed for use with Proofs of Custody.
 * @author Layr Labs, Inc.
 * @notice See the Dankrad's excellent article for an intro to Proofs of Custody:
 * https://dankradfeist.de/ethereum/2021/09/30/proofs-of-custody.html.
 */

interface IEphemeralKeyRegistry {
    // DATA STRUCTURES
    struct EphemeralKeyEntry {
        // the hash of the ephemeral key
        bytes32 ephemeralKeyHash;
        // when the ephemeral key started being used/will start being used
        uint32 startBlock;
        // when the ephemeral key was revealed. this is 0 if the ephemeral key for this entry has not been revealed yet.
        uint32 revealBlock;
    }

    /**
     * @notice Used by operator to post their first ephemeral key hashes via BLSRegistry (on registration).
     *         During revealing, the posted ephemeral keys will be checked against the ones committed on chain.
     * @param operator for signing on bomb-based queries
     * @param ephemeralKeyHash1 is the hash of the first ephemeral key to be used by `operator`
     * @param ephemeralKeyHash2 is the hash of the second ephemeral key to be used by `operator`
     * @dev This function can only be called by the registry itself.
     */
    function postFirstEphemeralKeyHashes(address operator, bytes32 ephemeralKeyHash1, bytes32 ephemeralKeyHash2) external;

    /**
     * @notice Used by the operator to reveal their unrevealed ephemeral keys via BLSRegistry (on deregistration).
     * @param startIndex is the index of the ephemeral key to reveal
     * @param prevEphemeralKeys are the previous ephemeral keys
     * @dev This function can only be called by the registry itself.
     */
    function revealLastEphemeralKeys(address operator, uint256 startIndex, bytes32[] memory prevEphemeralKeys) external;

    /**
     * @notice Used by the operator to commit to a new ephemeral key(s) and invalidate the current one.
     *         This would be called whenever 
     *              (1) an operator is going to run out of ephemeral keys and needs to put more on chain
     *              (2) an operator wants to reveal all ephemeral keys used before a certain block number
     *                  to propagate stake updates
     * @param ephemeralKeyHashes are the new ephemeralKeyHash(es) being committed
     * @param activeKeyIndex is the index of the caller's active ephemeral key
     */
    function commitNewEphemeralKeyHashesAndInvalidateActiveKey(bytes32[] calldata ephemeralKeyHashes, uint256 activeKeyIndex) external;

    /**
     * @notice Used by the operator to reveal an ephemeral key
     * @param index is the index of the ephemeral key to reveal
     * @param prevEphemeralKey is the previous ephemeral key
     * @dev This function should only be called when the key is already inactive and during the key's reveal period. Otherwise, the operator
     * can be slashed through a call to `verifyLeakedEphemeralKey`.
     */
    function revealEphemeralKey(uint256 index, bytes32 prevEphemeralKey) external;

    /**
     * @notice Used by watchers to prove that an operator hasn't revealed an ephemeral key when they should have.
     * @param operator is the entity with the stale unrevealed ephemeral key
     * @param index is the index of the stale entry
     */
    function verifyStaleEphemeralKey(address operator, uint256 index) external;

    /**
     * @notice Used by watchers to prove that an operator has inappropriately shared their ephemeral key with other entities.
     * @param operator is the entity that shared their ephemeral key
     * @param index is the index of the ephemeral key they shared
     * @param ephemeralKey is the preimage of the stored ephemeral key hash
     */
    function verifyLeakedEphemeralKey(address operator, uint256 index, bytes32 ephemeralKey) external;
    
    /**
     * @notice Returns the ephemeral key entry of the specified operator at the given blockNumber
     * @param operator is the entity whose ephemeral key entry is being retrieved
     * @param index is the index of the ephemeral key entry that was active during blockNumber
     * @param blockNumber the block number at which the returned entry's ephemeral key was active
     * @dev Reverts if index points to the incorrect public key. index should be calculated off chain before
     *      calling this method via looping through the array and finding the last entry that has a 
     *      startBlock <= blockNumber
     */
    function getEphemeralKeyEntryAtBlock(address operator, uint256 index, uint32 blockNumber) external returns(EphemeralKeyEntry memory);
}
