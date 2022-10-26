// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// TODO: validate this

/**
 * @title Small library for checking Spare Merkle proofs.
 * @author Layr Labs, Inc.
 * @notice This code takes inspiration from several sources, most notably [this implementation]
 * (https://github.com/rugpullindex/indexed-sparse-merkle-tree/blob/main/src/StateTree.sol)
 * and the [ETH2 deposit contract](https://etherscan.io/address/0x00000000219ab540356cbb839cbe05303d7705fa#code)
 */
abstract contract SparseMerkle {
    uint256 public immutable TREE_DEPTH;
    uint256 public immutable MAX_INDEX_VALUE;
    bytes32[] public ZERO_HASHES;

    modifier checkIndexValidity(uint256 index) {
        require(index <= MAX_INDEX_VALUE, "index value exceeds max index value");
        _;
    }

    modifier checkProofLength(uint256 proofLength) {
        require(proofLength <= TREE_DEPTH, "proofLength too high");
        _;
    }

    constructor(uint256 _TREE_DEPTH) {
        require(_TREE_DEPTH <= 256, "max tree depth is 256");
        require(_TREE_DEPTH >= 2, "min tree depth is 2");
        TREE_DEPTH = _TREE_DEPTH;
        uint256 maxIndexVal;
        if (_TREE_DEPTH != 256) {
            maxIndexVal = (2**_TREE_DEPTH) - 1;           
        } else {
            maxIndexVal = type(uint256).max;
        }
        MAX_INDEX_VALUE = maxIndexVal;
        ZERO_HASHES = new bytes32[](_TREE_DEPTH);
        uint256 i;
        while (i < _TREE_DEPTH - 1) {
            ZERO_HASHES[i + 1] = keccak256(abi.encodePacked(ZERO_HASHES[i], ZERO_HASHES[i]));
            unchecked {
                ++i;
            }
        }
    }

    function checkInclusion(
        bytes32[] calldata proofElements,
        uint256 nodeWrittenBitmap,
        uint256 index,
        bytes32 leafHash,
        bytes32 expectedRoot
    )
        public view 
        checkIndexValidity(index)
        checkProofLength(proofElements.length)
        returns (bool)
    {
        return (expectedRoot == _calculateRoot(proofElements, nodeWrittenBitmap, index, leafHash));
    }

    function _calculateRoot(
        bytes32[] calldata proofElements,
        uint256 nodeWrittenBitmap,
        uint256 index,
        bytes32 leafHash
    )
        internal view returns (bytes32)
    {
        uint256 mask;
        for (uint256 i = 0; i < TREE_DEPTH;) {
            //take a '1' and move it to the i-th index from right-to-left (little endian, 0-indexed)
            mask = (1 << i);
            // check if i-th bit of 'index' is 1
            if ((index & mask) != 0) {
                /**
                 * check if i-th bit of 'nodeWrittenBitmap' is 1,
                 * indicating that the node at the i-th index *has* been written to
                 */
                if ((nodeWrittenBitmap & mask) != 0) {
                    leafHash = keccak256(abi.encode(proofElements[i], leafHash));
                /**
                 * otherwise the i-th bit of 'nodeWrittenBitmap' is 0,
                 * indicating that the node at the i-th index has *not* been written to
                 */
                } else {
                    leafHash = keccak256(abi.encode(ZERO_HASHES[i], leafHash));
                }
            // otherwise i-th bit of 'index' is 0
            } else {
                /**
                 * check if i-th bit of 'nodeWrittenBitmap' is 1,
                 * indicating that the node at the i-th index *has* been written to
                 */
                if ((nodeWrittenBitmap & mask) != 0) {
                    leafHash = keccak256(abi.encode(leafHash, proofElements[i]));
                /**
                 * otherwise the i-th bit of 'nodeWrittenBitmap' is 0,
                 * indicating that the node at the i-th index has *not* been written to
                 */
                } else {
                    leafHash = keccak256(abi.encode(leafHash, ZERO_HASHES[i]));
                }
            }
            
            // increment the loop, no chance for overflow
            unchecked {
                ++i;
            }
        }
        return leafHash;
    }
}