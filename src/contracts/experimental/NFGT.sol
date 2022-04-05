// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

//TODO: inherit from more efficient implementation
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract Naive_NFGT is ERC1155 {
    uint256 internal immutable TREE_DEPTH;
    uint256 internal immutable MAX_SLOT_VALUE;
    uint256 internal immutable ORIGIN_ID;
    //tokenId => slot => slotContents => newTokenId
    mapping(uint256 => mapping(uint256 => mapping(bytes32 => uint256))) public tokenChanges;
    //tokenId => parent
    mapping(uint256 => uint256) public tokenParents;
    //_ancestry[tokenA][tokenB] will be 'true' in the event that tokenB has been proven to be an ancestor of tokenA
    //in the event that _ancestry[tokenA][tokenB] is false, nothing is proven
    mapping(uint256 => mapping (uint256 => bool)) internal _ancestry;
    bytes32[] internal ZERO_HASHES;

    modifier checkSlotValidity(uint256 slot) {
        require(slot <= MAX_SLOT_VALUE, "slot value exceeds max slot value");
        _;
    }

    constructor(string memory _uri, uint256 _TREE_DEPTH) ERC1155(_uri) {
        require(_TREE_DEPTH <= 256, "max tree depth is 256");
        require(_TREE_DEPTH >= 2, "min tree depth is 2");
        TREE_DEPTH = _TREE_DEPTH;
        uint256 maxSlotVal;
        if (_TREE_DEPTH != 256) {
            maxSlotVal = (2**_TREE_DEPTH) - 1;           
        } else {
            maxSlotVal = type(uint256).max;
        }
        MAX_SLOT_VALUE = maxSlotVal;
        ZERO_HASHES = new bytes32[](_TREE_DEPTH);
        uint256 i;
        while (i < _TREE_DEPTH - 1) {
            ZERO_HASHES[i + 1] = keccak256(abi.encodePacked(ZERO_HASHES[i], ZERO_HASHES[i]));
            unchecked {
                ++i;
            }
        }
        ORIGIN_ID = uint256(ZERO_HASHES[TREE_DEPTH - 1]);
    }

    function uint256ToBytes32(uint256 input) public pure returns (bytes32) {
        return bytes32(input);
    }

    function bytes32ToUint256(bytes32 input) public pure returns (uint256) {
        return uint256(input);
    }

    function proveLeaf(
        uint256 tokenId,
        uint256 slot,
        bytes32 slotContents,
        uint256 nodeWrittenBitmap,
        bytes32[] calldata proofElements)
        public view checkSlotValidity(slot) returns (bool) 
    {
        bytes32 root = bytes32(tokenId);
        uint256 mask;
        uint256 proofElementIndex;
        bool leftFork;
        bytes32 node = slotContents;
        uint256 i;
        while (i < TREE_DEPTH) {
            //take a '1' and move it to the i-th slot from right-to-left (little endian)
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

    function findLeafOutcome(
        uint256 tokenId,
        uint256 slot,
        bytes32 contentsToWrite,
        uint256 nodeWrittenBitmap,
        bytes32[] calldata proofElements)
        public view checkSlotValidity(slot) returns (uint256) 
    {
        bytes32 root = bytes32(tokenId);
        uint256 mask;
        uint256 proofElementIndex;
        bool leftFork;
        bytes32 node;
        bytes32 newNode = contentsToWrite;
        uint256 i;
        while (i < TREE_DEPTH) {
            //take a '1' and move it to the i-th slot from right-to-left (little endian)
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

    function _writeLeafToToken(
        uint256 tokenId,
        uint256 slot,
        bytes32 contentsToWrite,
        uint256 nodeWrittenBitmap,
        bytes32[] calldata proofElements)
        internal returns (uint256) 
    {
        uint256 newTokenId = findLeafOutcome(tokenId, slot, contentsToWrite, nodeWrittenBitmap, proofElements);
        tokenChanges[tokenId][slot][contentsToWrite] = newTokenId;
        tokenParents[newTokenId] = tokenId;
        return newTokenId;
    }

    //TODO: sort out more about permissions / when + how this function is invoked
    function _convertTokens(
        address owner,
        uint256 tokenAmount,
        uint256 tokenId,
        uint256 slot,
        bytes32 slotContents,
        uint256 newTokenId) internal 
    {
        require(tokenChanges[tokenId][slot][slotContents] == newTokenId, "conversion invalid");
        //TODO: more efficient method here?
        _burn(owner, tokenId, tokenAmount);
        _mint(owner, newTokenId, tokenAmount, "");
    }

    //performs brute-force search, stepping backwards along descendant's ancestry until ancestor is reached or history runs out
    function _proveAncestrySimple(uint256 descendant, uint256 ancestor) internal returns (bool) {
        uint256 latestAncestor = tokenParents[descendant];
        while ((latestAncestor != ancestor) && (latestAncestor != ORIGIN_ID)) {
            latestAncestor = tokenParents[latestAncestor];
        }
        if (latestAncestor == ancestor) {
            _ancestry[descendant][ancestor] = true;
            return true;
        } else {
            return false;
        }
    }

    //checks storage, then performs brute-force search if result in storage is not 'true'
    function checkAncestrySimple(uint256 descendant, uint256 ancestor) public returns (bool) {
        if (_ancestry[descendant][ancestor] == true) {
            return true;
        } else {
            return _proveAncestrySimple(descendant, ancestor);
        }
    }

    //equivalent to '_proveAncestrySimple', but does not modify state
    function _proveAncestrySimpleView(uint256 descendant, uint256 ancestor) internal view returns (bool) {
        uint256 latestAncestor = tokenParents[descendant];
        while ((latestAncestor != ancestor) && (latestAncestor != ORIGIN_ID)) {
            latestAncestor = tokenParents[latestAncestor];
        }
        if (latestAncestor == ancestor) {
            return true;
        } else {
            return false;
        }
    }

    //equivalent to 'checkAncestrySimple', but does not modify state
    function checkAncestrySimpleView(uint256 descendant, uint256 ancestor) public view returns (bool) {
        if (_ancestry[descendant][ancestor] == true) {
            return true;
        } else {
            return _proveAncestrySimpleView(descendant, ancestor);
        }
    }

}