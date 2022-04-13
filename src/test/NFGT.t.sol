// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../contracts/experimental/NFGT.sol";

import "ds-test/test.sol";

import "../contracts/utils/ERC165_Universal.sol";
import "../contracts/utils/ERC1155TokenReceiver.sol";

import "./CheatCodes.sol";

contract NFGT_Tester is DSTest, ERC165_Universal, ERC1155TokenReceiver {

    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);
    NFGT public nfgt;
    uint256 ORIGIN_ID;
    uint256 TREE_DEPTH = 2;

    function setUp() public {
        string memory nfgt_name = "nfgt name";
        uint256 _initSupply = 1e24;
        nfgt = new NFGT(nfgt_name, TREE_DEPTH, _initSupply);
        ORIGIN_ID = nfgt.ORIGIN_ID();
    }

    function testNfgtDeploymentSuccessful() public {
        assertTrue(
            address(nfgt) != address(0),
            "nfgt failed to deploy"
        );
        // emit log_named_uint("ORIGIN_ID", ORIGIN_ID);
        // emit log_named_bytes32("bytes32(ORIGIN_ID)", bytes32(ORIGIN_ID));
        // for (uint256 i; i < TREE_DEPTH; ++i) {
        //     emit log_named_uint("i", i);
        //     emit log_named_bytes32("ZERO_HASHES", nfgt.ZERO_HASHES(i));
        // }
    }

    function testFindLeafOutcome() public view returns (uint256){
        uint256 tokenId = ORIGIN_ID;
        uint256 slot = uint256(0);
        bytes32 contentsToWrite = 0x0102030405060708091011121314151617181920212223242526272829303132;
        uint256 nodeWrittenBitmap = uint256(0);
        //don't need to fill in proofElements arrary since nothing has been written yet
        bytes32[] memory proofElements = new bytes32[](0);
        uint256 newTokenId = nfgt.findLeafOutcome(tokenId, slot, contentsToWrite, nodeWrittenBitmap, proofElements);
        // emit log_named_uint("newTokenId", newTokenId);
        return newTokenId;
    }

    function testWritingLeaf() public returns (uint256) {
        uint256 tokenId = ORIGIN_ID;
        uint256 slot = uint256(0);
        bytes32 contentsToWrite = 0x0102030405060708091011121314151617181920212223242526272829303132;
        uint256 nodeWrittenBitmap = uint256(0);
        //don't need to fill in proofElements arrary since nothing has been written yet
        bytes32[] memory proofElements = new bytes32[](0);
        uint256 newTokenId = nfgt.writeLeafToToken(tokenId, slot, contentsToWrite, nodeWrittenBitmap, proofElements);
        // emit log_named_uint("newTokenId", newTokenId);
        return newTokenId;
    }

    function testWritingTwoLeaves() public returns (uint256) {
        uint256 tokenId = testWritingLeaf();
        uint256 slot = uint256(1);
        bytes32 contentsWritten = 0x0102030405060708091011121314151617181920212223242526272829303132;
        bytes32 contentsToWrite = 0x0102030405060708091011121314151617181920212223242526272829303132;
        //the only proof element we need to provide is the already written leaf, since it is adjacent to this one
        uint256 nodeWrittenBitmap = uint256(1);
        bytes32[] memory proofElements = new bytes32[](1);
        proofElements[0] = contentsWritten;
        uint256 newTokenId = nfgt.writeLeafToToken(tokenId, slot, contentsToWrite, nodeWrittenBitmap, proofElements);
        // emit log_named_uint("newTokenId", newTokenId);
        return newTokenId;
    }

    function testWritingThreeLeaves() public returns (uint256) {
        uint256 tokenId = testWritingTwoLeaves();
        uint256 slot = uint256(2);
        bytes32 contentsWritten = 0x0102030405060708091011121314151617181920212223242526272829303132;
        bytes32 contentsToWrite = 0x0102030405060708091011121314151617181920212223242526272829303132;
        uint256 nodeWrittenBitmap = uint256(2);
        //the only proof element we need to provide is the node corresponding to the two already written leaves
        bytes32[] memory proofElements = new bytes32[](1);
        proofElements[0] = keccak256(abi.encodePacked(contentsWritten, contentsWritten));
        uint256 newTokenId = nfgt.writeLeafToToken(tokenId, slot, contentsToWrite, nodeWrittenBitmap, proofElements);
        // emit log_named_uint("newTokenId", newTokenId);
        return newTokenId;
    }

    function testWritingFourLeaves() public returns (uint256) {
        uint256 tokenId = testWritingThreeLeaves();
        uint256 slot = uint256(3);
        bytes32 contentsWritten = 0x0102030405060708091011121314151617181920212223242526272829303132;
        bytes32 contentsToWrite = 0x0102030405060708091011121314151617181920212223242526272829303132;
        uint256 nodeWrittenBitmap = uint256(3);
        bytes32[] memory proofElements = new bytes32[](2);
        //we need to provide the adjacent (already written) leaf contents, plus the node corresponding to the other already-written leaves
        proofElements[0] = contentsWritten;
        proofElements[1] = keccak256(abi.encodePacked(contentsWritten, contentsWritten));
        uint256 newTokenId = nfgt.writeLeafToToken(tokenId, slot, contentsToWrite, nodeWrittenBitmap, proofElements);
        // emit log_named_uint("newTokenId", newTokenId);
        return newTokenId;
    }
}
