// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/**
 * @title Interface for an Ephemeral Key Registry, designed for use with Proofs of Custody.
 * @author Layr Labs, Inc.
 * @notice See the Dankrad's excellent article for an intro to Proofs of Custody:
 * https://dankradfeist.de/ethereum/2021/09/30/proofs-of-custody.html.
 */

interface IEphemeralKeyRegistry {
    function postFirstEphemeralKeyHashes(address operator, bytes32 ephemeralKeyHash1, bytes32 ephemeralKeyHash2) external;

    function revealLastEphemeralKeys(address operator, uint256 startIndex, bytes32[] memory prevEpheremeralKeys) external;

    function revealEphemeralKey(uint256 index, bytes32 prevEpheremeralKey) external;

    function verifyStaleEphemeralKey(address operator, uint256 index) external;

    function verifyLeakedEphemeralKey(address operator, uint256 index, bytes32 ephemeralKey) external;
    
    function getEphemeralKeyAtBlock(address operator, uint256 index, uint32 blockNumber) external returns(bytes32);
}
