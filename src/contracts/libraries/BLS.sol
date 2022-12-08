// SPDX-License-Identifier: UNLICENSED AND MIT
// several functions are adapted from https://github.com/HarryR/solcrypto/blob/master/contracts/altbn128.sol (MIT license)
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
    function hashToG1(bytes32 _x) internal view returns (uint256, uint256) {
        uint256 beta = 0;
        uint256 y = 0;

        // XXX: Gen Order (n) or Field Order (p) ?
        uint256 x = uint256(_x) % FP_MODULUS;

        while( true ) {
            (beta, y) = FindYforX(x);

            // y^2 == beta
            if( beta == mulmod(y, y, FP_MODULUS) ) {
                return (x, y);
            }

            x = addmod(x, 1, FP_MODULUS);
        }
        return (0, 0);
    }


    /**
    * Given X, find Y
    *
    *   where y = sqrt(x^3 + b)
    *
    * Returns: (x^3 + b), y
    */
    function FindYforX(uint256 x)
        internal view returns(uint256, uint256)
    {
        // beta = (x^3 + b) % p
        uint256 beta = addmod(mulmod(mulmod(x, x, FP_MODULUS), x, FP_MODULUS), 3, FP_MODULUS);

        // y^2 = x^3 + b
        // this acts like: y = sqrt(beta) = beta^((p+1) / 4)
        uint256 y = expMod(beta, 0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52, FP_MODULUS);

        return (beta, y);
    }

    function expMod(uint256 _base, uint256 _exponent, uint256 _modulus) internal view returns (uint256 retval) {
        bool success;
        uint256[1] memory output;
        uint[6] memory input;
        input[0] = 0x20;        // baseLen = new(big.Int).SetBytes(getData(input, 0, 32))
        input[1] = 0x20;        // expLen  = new(big.Int).SetBytes(getData(input, 32, 32))
        input[2] = 0x20;        // modLen  = new(big.Int).SetBytes(getData(input, 64, 32))
        input[3] = _base;
        input[4] = _exponent;
        input[5] = _modulus;
        assembly {
            success := staticcall(sub(gas(), 2000), 5, input, 0xc0, output, 0x20)
            // Use "invalid" to make gas estimation work
            switch success case 0 { invalid() }
        }
        require(success);
        return output[0];
    }

}