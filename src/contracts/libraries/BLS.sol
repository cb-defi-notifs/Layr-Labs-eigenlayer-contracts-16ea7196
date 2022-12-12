// SPDX-License-Identifier: UNLICENSED AND MIT
// several functions are from https://github.com/ChihChengLiang/bls_solidity_python/blob/master/contracts/BLS.sol (MIT license)
// remainder is UNLICENSED
pragma solidity ^0.8.9;

import "./BN254.sol";

/**
 * @title Library for operations related to BLS Signatures used in EigenLayer middleware.
 * @author Layr Labs, Inc. with credit to Chih Cheng Liang
 * @notice Uses the BN254 curve.
 */
library BLS {
    // BN 254 CONSTANTS
    // modulus for the underlying field F_p of the elliptic curve
    uint256 internal constant FP_MODULUS = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
    // modulus for the underlying field F_r of the elliptic curve
    uint256 internal constant FR_MODULUS = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

    // primitive root of unity 
    uint256 internal constant OMEGA = 10359452186428527605436343203440067497552205259388878191021578220384701716497;

    // negation of the generator of group G2
    /**
     * @dev Generator point lies in F_q2 is of the form: (x0 + ix1, y0 + iy1).
     */
    uint256 internal constant nG2x1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 internal constant nG2x0 = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 internal constant nG2y1 = 17805874995975841540914202342111839520379459829704422454583296818431106115052;
    uint256 internal constant nG2y0 = 13392588948715843804641432497768002650278120570034223513918757245338268106653;

    // generator of group G2
    /**
     * @dev Generator point lies in F_q2 is of the form: (x0 + ix1, y0 + iy1).
     */
    uint256 internal constant G2x1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 internal constant G2x0 = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 internal constant G2y1 = 4082367875863433681332203403145435568316851327593401208105741076214120093531;
    uint256 internal constant G2y0 = 8495653923123431417604973247489272438418190587263600148770280649306958101930;

    bytes32 internal constant powersOfTauMerkleRoot = 0x22c998e49752bbb1918ba87d6d59dd0e83620a311ba91dd4b2cc84990b31b56f;


    // first power of srs in G2
    // change in production
    uint256 internal constant G2SRSx1 = 7912312892787135728292535536655271843828059318189722219035249994421084560563;
    uint256 internal constant G2SRSx0 = 21039730876973405969844107393779063362038454413254731404052240341412356318284;
    uint256 internal constant G2SRSy1 = 18697407556011630376420900106252341752488547575648825575049647403852275261247;
    uint256 internal constant G2SRSy0 = 7586489485579523767759120334904353546627445333297951253230866312564920951171;
  

    function hashG1Point(BN254.G1Point memory pk) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(pk.X, pk.Y));
    }

    function hashPubkey(uint256[4] memory pk) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3]));
    }

    function hashPubkey(uint256[6] memory pk) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3]));
    }

    /**
     * @notice same as hashToPoint function in https://github.com/ChihChengLiang/bls_solidity_python/blob/master/contracts/BLS.sol
     */
    function hashToG1(bytes32 _x) internal view returns (uint256 x, uint256 y) {
        x = uint256(_x) % FP_MODULUS;
        bool found = false;
        while (true) {
            y = mulmod(x, x, FP_MODULUS);
            y = mulmod(y, x, FP_MODULUS);
            y = addmod(y, 3, FP_MODULUS);
            (y, found) = sqrt(y);
            if (found) {
                return (x, y);
            }
            x = addmod(x, 1, FP_MODULUS);
        }
    }

    function sqrt(uint256 xx) internal view returns (uint256 x, bool hasRoot) {
        bool callSuccess;
        assembly {
            let freemem := mload(0x40)
            mstore(freemem, 0x20)
            mstore(add(freemem, 0x20), 0x20)
            mstore(add(freemem, 0x40), 0x20)
            mstore(add(freemem, 0x60), xx)
            // (N + 1) / 4 = 0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52
            mstore(add(freemem, 0x80), 0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52)
            // N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            mstore(add(freemem, 0xA0), 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47)
            callSuccess := staticcall(sub(gas(), 2000), 5, freemem, 0xC0, freemem, 0x20)
            x := mload(freemem)
            hasRoot := eq(xx, mulmod(x, x, FP_MODULUS))
        }
        require(callSuccess, "BLS: sqrt modexp call failed");
    }
}