// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

//small library for dealing with efficiently-packed signatures, where parameters v,r,s are packed into vs and r (64 bytes instead of 65)
library SignatureCompaction {
    bytes32 constant internal HALF_CURVE_ORDER = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    function ecrecoverPacked(bytes32 hash, bytes32 r, bytes32 vs) public pure returns (address) {
        return ecrecover(
            hash,
            //recover v (parity)
            27 + uint8(uint256(vs >> 255)),
            r,
            //recover s
            //bytes32(uint(vs) & (~uint(0) >> 1))
            bytes32(uint256(vs) & (0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff))
        );
    }

    function packSignature(bytes32 r, bytes32 s, uint8 v) public pure returns (bytes32, bytes32) {
        require(s <= HALF_CURVE_ORDER, "malleable signature, s too high");
        //v parity is a single bit, encoded as either v = 27 or v = 28 -- in order to recover the bit we subtract 27
        bytes32 vs = bytes32(uint256(v - 27) | uint256(s));
        return (r, vs);
    }

    //same as above, except doesn't take 'r' as argument since it is unneeded
    function packVS(bytes32 s, uint8 v) public pure returns (bytes32) {
        require(s <= HALF_CURVE_ORDER, "malleable signature, s too high");
        //v parity is a single bit, encoded as either v = 27 or v = 28 -- in order to recover the bit we subtract 27
        return bytes32(uint256(v - 27) | uint256(s));
    }
}