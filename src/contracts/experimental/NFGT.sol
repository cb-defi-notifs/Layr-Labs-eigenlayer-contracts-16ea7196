// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

//TODO: inherit from more efficient implementation
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract Naive_NFGT is ERC1155 {
    constructor() ERC1155("https://insert-uri-here.com") {
    }

    uint256 internal constant TREE_DEPTH = 256;
    bytes32[TREE_DEPTH] internal ZERO_HASHES;
    //tokenId => slot => slotContents => newTokenId
    mapping(uint256 => mapping(uint256 => mapping(bytes32 => uint256))) public tokenChanges;
    //tokenId => parent
    mapping(uint256 => uint256) public tokenParents;

    function setZeroHashes() internal {
        uint256 i;
        while (i < TREE_DEPTH - 1) {
            ZERO_HASHES[i + 1] = keccak256(abi.encodePacked(ZERO_HASHES[i], ZERO_HASHES[i]));
            unchecked {
                ++i;
            }
        }
    }

    function uint256ToBytes32(uint256 input) public pure returns (bytes32) {
        return bytes32(input);
    }

    function bytes32ToUint256(bytes32 input) public pure returns (uint256) {
        return uint256(input);
    }

    function proveLeaf(uint256 tokenId, uint256 slot, bytes32 slotContents, uint256 nodeWrittenBitmap, bytes32[] calldata proofElements) public view returns (bool) {
        bytes32 root = bytes32(tokenId);
        uint256 mask;
        uint256 i;
        uint256 proofElementIndex;
        bool leftFork;
        bytes32 node = slotContents;
        while (i < TREE_DEPTH) {
            mask = (1 << i);
            //i.e. if slot does not have a '1' at the i-th bit
            leftFork = ((slot & mask) == 0);
            //i.e. if the node at index i has not yet been written to
            if ((nodeWrittenBitmap & mask) == 0) {
                if (leftFork) {
                    node = keccak256(abi.encodePacked(node, ZERO_HASHES[i]));
                } else {
                    node = keccak256(abi.encodePacked(ZERO_HASHES[i], node));                    
                }
            } else {
                if (leftFork) {
                    node = keccak256(abi.encodePacked(node, proofElements[proofElementIndex]));                    
                } else {
                    node = keccak256(abi.encodePacked(proofElements[proofElementIndex], node));                    
                }
                unchecked {
                    ++proofElementIndex;
                }
            }
            unchecked {
                ++i;
            }
        }
        return (node == root);
    }

    function writeLeafOutcome(uint256 tokenId, uint256 slot, bytes32 contentsToWrite, uint256 nodeWrittenBitmap, bytes32[] calldata proofElements) public view returns (uint256) {
        bytes32 root = bytes32(tokenId);
        uint256 mask;
        uint256 i;
        uint256 proofElementIndex;
        bool leftFork;
        bytes32 node;
        bytes32 newNode = contentsToWrite;
        while (i < TREE_DEPTH) {
            mask = (1 << i);
            //i.e. if slot does not have a '1' at the i-th bit
            leftFork = ((slot & mask) == 0);
            //i.e. if the node at index i has not yet been written to
            if ((nodeWrittenBitmap & mask) == 0) {
                if (leftFork) {
                    node = keccak256(abi.encodePacked(node, ZERO_HASHES[i]));
                    newNode = keccak256(abi.encodePacked(newNode, ZERO_HASHES[i]));
                } else {
                    node = keccak256(abi.encodePacked(ZERO_HASHES[i], node));                    
                    newNode = keccak256(abi.encodePacked(ZERO_HASHES[i], newNode));                    
                }
            } else {
                if (leftFork) {
                    node = keccak256(abi.encodePacked(node, proofElements[proofElementIndex]));                    
                    newNode = keccak256(abi.encodePacked(newNode, proofElements[proofElementIndex]));                    
                } else {
                    node = keccak256(abi.encodePacked(proofElements[proofElementIndex], node));                    
                    newNode = keccak256(abi.encodePacked(proofElements[proofElementIndex], newNode));                    
                }
                unchecked {
                    ++proofElementIndex;
                }
            }
            unchecked {
                ++i;
            }
        }
        require(node == root, "proof of existing tokenId is wrong");
        uint256 newTokenId = uint256(newNode);
        return newTokenId;
    }

    function _writeLeafToToken(uint256 tokenId, uint256 slot, bytes32 contentsToWrite, uint256 nodeWrittenBitmap, bytes32[] calldata proofElements) internal returns (uint256) {
        uint256 newTokenId = writeLeafOutcome(tokenId, slot, contentsToWrite, nodeWrittenBitmap, proofElements);
        tokenChanges[tokenId][slot][contentsToWrite] = newTokenId;
        tokenParents[newTokenId] = tokenId;
        return newTokenId;
    }

    function _convertTokens(uint256 tokenId, uint256 slot, bytes32 slotContents, uint256 newTokenId) internal view {
        require(tokenChanges[tokenId][slot][slotContents] == newTokenId, "conversion invalid");
        //TODO: actually convert to new tokenId
    }










    //_ancestry[tokenA][tokenB] will be 'true' in the event that tokenB has been proven to be an ancestor of tokenA
    //in the event that _ancestry[tokenA][tokenB] is false, nothing is proven
    mapping(uint256 => mapping (uint256 => bool)) internal _ancestry;

    function _proveAncestrySimple(uint256 descendant, uint256 ancestor) internal returns (bool) {
        uint256 latestAncestor = tokenParents[descendant];
        while ((latestAncestor != ancestor) && (latestAncestor != 0)) {
            latestAncestor = tokenParents[latestAncestor];
        }
        if (latestAncestor == ancestor) {
            _ancestry[descendant][ancestor] = true;
            return true;
        } else {
            return false;
        }
    }

    function checkAncestrySimple(uint256 descendant, uint256 ancestor) public returns (bool) {
        if (_ancestry[descendant][ancestor] == true) {
            return true;
        } else {
            return _proveAncestrySimple(descendant, ancestor);
        }
    }
}