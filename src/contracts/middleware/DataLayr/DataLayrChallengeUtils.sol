// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrServiceManager.sol";
import "../../libraries/Merkle.sol";

contract DataLayrChallengeUtils {
    // modulus for the underlying field F_q of the elliptic curve
    uint256 constant MODULUS =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;
    // negation of the generators of group G2
    /**
     @dev Generator point lies in F_q2 is of the form: (x0 + ix1, y0 + iy1).
     */
    uint256 constant nG2x1 =
        11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 constant nG2x0 =
        10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 constant nG2y1 =
        17805874995975841540914202342111839520379459829704422454583296818431106115052;
    uint256 constant nG2y0 =
        13392588948715843804641432497768002650278120570034223513918757245338268106653;

    constructor() {}

    function checkInclusionExclusionInNonSigner(
        bytes32 operatorPubkeyHash,
        uint256 nonSignerIndex,
        IDataLayrServiceManager.SignatoryRecordMinusDumpNumber
            calldata signatoryRecord
    ) public {
        if (signatoryRecord.nonSignerPubkeyHashes.length != 0) {
            // check that uint256(nspkh[index]) <  uint256(operatorPubkeyHash)
            require(
                //they're either greater than everyone in the nspkh array
                (nonSignerIndex ==
                    signatoryRecord.nonSignerPubkeyHashes.length &&
                    uint256(
                        signatoryRecord.nonSignerPubkeyHashes[
                            nonSignerIndex - 1
                        ]
                    ) <
                    uint256(operatorPubkeyHash)) ||
                    //or nonSigner index is greater than them
                    (uint256(
                        signatoryRecord.nonSignerPubkeyHashes[nonSignerIndex]
                    ) > uint256(operatorPubkeyHash)),
                "Wrong index"
            );

            //  check that uint256(operatorPubkeyHash) > uint256(nspkh[index - 1])
            if (nonSignerIndex != 0) {
                //require that the index+1 is before where operatorpubkey hash would be
                require(
                    uint256(
                        signatoryRecord.nonSignerPubkeyHashes[
                            nonSignerIndex - 1
                        ]
                    ) < uint256(operatorPubkeyHash),
                    "Wrong index"
                );
            }
        }
    }

    function getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(
        // bytes calldata header
        bytes calldata
    )
        public
        pure
        returns (
            uint256[2] memory,
            uint48,
            uint32,
            uint32
        )
    {
        // return x, y coordinate of overall data poly commitment
        // then return degree of multireveal polynomial
        uint256[2] memory point = [uint256(0), uint256(0)];
        uint48 degree = 0;
        uint32 numSys = 0;
        uint32 numPar = 0;
        uint256 pointer = 4;
        //uint256 length = 0;  do not need length

        assembly {
            // get data location
            pointer := calldataload(pointer)
        }

        unchecked {
            // uncompensate signature length
            pointer += 36; // 4 + 32
        }

        assembly {
            mstore(point, calldataload(pointer))
            mstore(add(point, 0x20), calldataload(add(pointer, 32)))

            degree := shr(224, calldataload(add(pointer, 64)))

            numSys := shr(224, calldataload(add(pointer, 68)))
            numPar := shr(224, calldataload(add(pointer, 72)))
        }

        return (point, degree, numSys, numPar);
    }

    function getLeadingCosetIndexFromHighestRootOfUnity(
        uint32 i,
        uint32 numSys,
        uint32 numPar
    ) public pure returns (uint32) {
        uint32 numNode = numSys + numPar;
        uint32 numSysE = uint32(nextPowerOf2(numSys));
        uint32 ratio = numNode / numSys + (numNode % numSys == 0 ? 0 : 1);
        uint32 numNodeE = uint32(nextPowerOf2(numSysE * ratio));

        if (i < numSys) {
            return
                (reverseBitsLimited(uint32(numNodeE), uint32(i)) * 512) /
                numNodeE;
        } else if (i < numNodeE - (numSysE - numSys)) {
            return
                (reverseBitsLimited(
                    uint32(numNodeE),
                    uint32((i - numSys) + numSysE)
                ) * 512) / numNodeE;
        } else {
            revert("Cannot create number of frame higher than possible");
        }
        revert("Cannot create number of frame higher than possible");
        return 0;
    }

    function reverseBitsLimited(uint32 length, uint32 value)
        public
        pure
        returns (uint32)
    {
        uint32 unusedBitLen = 32 - uint32(log2(length));
        return reverseBits(value) >> unusedBitLen;
    }

    function reverseBits(uint32 value) public pure returns (uint32) {
        uint256 reversed = 0;
        for (uint i = 0; i < 32; i++) {
            uint256 mask = 1 << i;
            if (value & mask != 0) {
                reversed |= (1 << (31 - i));
            }
        }
        return uint32(reversed);
    }

    //takes the log base 2 of n and returns it
    function log2(uint256 n) internal pure returns (uint256) {
        require(n > 0, "Log must be defined");
        uint256 log = 0;
        while (n >> log != 1) {
            log++;
        }
        return log;
    }

    //finds the next power of 2 greater than n and returns it
    function nextPowerOf2(uint256 n) public pure returns (uint256) {
        uint256 res = 1;
        while (1 << res < n) {
            res++;
        }
        res = 1 << res;
        return res;
    }

    // gets the merkle root of a tree where all the leaves are the hashes of the zero/vanishing polynomials of the given multireveal
    // degree at different roots of unity. We are assuming a max of 512 datalayr nodes  right now, so, for merkle root for "degree"
    // will be of the tree where the leaves are the hashes of the G2 kzg commitments to the following polynomials:
    // l = degree (for brevity)
    // w^(512*l) = 1
    // (s^l - 1), (s^l - w^l), (s^l - w^2l), (s^l - w^3l), (s^l - w^4l), ...
    // we have precomputed these values and return them directly because it's cheap. currently we
    // tolerate up to degree 2^11, which means up to (31 bytes/point)(1024 points/dln)(512 dln) = 16 MB in a datastore
    function getZeroPolyMerkleRoot(uint256 degree) external returns (bytes32) {
        uint256 log = log2(degree);

        if (log == 0) {
            return
                0xa059dfdeb6fc546a13d30cb6c9906fce0f0e0272bdd70281145a9fa6780afdc8;
        } else if (log == 1) {
            return
                0x10e0b40abb47ec8e2a5c7ddca2cfb51a70e7432091d8a2a35c1856d3923f1d71;
        } else if (log == 2) {
            return
                0xf71bc765bde3e267c636cf5bd3e5a96664f0fe9e01b8d54e4b01afe15014e76c;
        } else if (log == 3) {
            return
                0xe8e7782cf9886e6d69dcbc3b7a2f58ced7c06ddb35acf8e5a5d58c887b34874a;
        } else if (log == 4) {
            return
                0x0598c3a0c6a1d2ccfd2c93bc96eac392dfe3d0d445c97c46441152943318e63f;
        } else if (log == 5) {
            return
                0x41cb97c473072fddba8ed717f8dc7b7e0fd5dc744a8ba2a9e253ad8d78dfa32f;
        } else if (log == 6) {
            return
                0x26f7374da50cbfe17ef3cf487f51ea44f555399866ad742ea06462334f4f66b4;
        } else if (log == 7) {
            return
                0xbca38bf3ddb80fd127340860bab7f8ae429c34021b7190cc3f7d4713146783ad;
        } else if (log == 8) {
            return
                0xf9ebc418bccf0d6a95b8ae266988021be7aa7b724ea59b8f7e0ad5b267e5b946;
        } else if (log == 9) {
            return
                0xb0748c026000b13eebd6f09e068bb8bc2222719356dda302885ceea08ca71880;
        } else if (log == 10) {
            return
                0xacfd8fb390342be6ef9ccfc6a85d63efe7aedf83ca6c4d57f5b53ebb209f9022;
        } else if (log == 11) {
            return
                0x062b58a8cf8d73d7d75d1eabb10c8f578ee9e943478db743fddb03bac8ddcfb4;
        } else {
            revert("Log not in valid range");
        }
    }

    // opens up kzg commitment c(x) at r and makes sure c(r) = s. proof (pi) is in G2 to allow for calculation of Z in G1
    function openPolynomialAtPoint(uint256[2] calldata c, uint256[4] calldata pi, uint256 r, uint256 s) public returns(bool) {
        uint256[12] memory pairingInput;
        //calculate -g1*r and store in first 2 slots of input      -g1 = (1, -2) btw
        pairingInput[0] = 1;
        pairingInput[1] = MODULUS - 2;
        pairingInput[2] = r;
        assembly {
            // @dev using precompiled contract at 0x07 to do G1 scalar multiplication on elliptic curve alt_bn128

            if iszero(
                call(
                    // forward all gas
                    not(0),
                    // call ecMul precompile
                    0x07,
                    // send no value
                    0,
                    // send args starting from pairingInput[0]
                    pairingInput,
                    // send 96 bytes of arguments, i.e. pairingInput[0], pairingInput[1], and pairingInput[2]
                    0x60,
                    // store return data starting from pairingInput[0]
                    pairingInput,
                    // store 64 bytes of return data, i.e. overwrite pairingInput[0] & pairingInput[1] with the return data
                    0x40
                )
            ) {
                // revert if the call to the precompile failed
                revert(0, 0)
            }
        }

        //add [x]_1 + (-r*g1) = Z and store in first 2 slots of input
        //TODO: SWITCH THESE TO [x]_1 of Powers of Tau!
        pairingInput[2] = 1;
        pairingInput[3] = 2;

        assembly {
            // @dev using precompiled contract at 0x06 to do point addition on elliptic curve alt_bn128

            // add together the alt_bn128 points defined by (pairingInput[0], pairingInput[1]) and (pairingInput[2], pairingInput[3])
            // store resultant point in (pairingInput[0], pairingInput[1])
            if iszero(
                call(
                    // forward all gas
                    not(0),
                    // call ecAdd precompile
                    0x06,
                    // send no value
                    0,
                    // send args starting from pairingInput[0]
                    pairingInput,
                    // send 128 bytes of arguments, i.e. pairingInput[0], pairingInput[1], pairingInput[2], and pairingInput[3]
                    0x80,
                    // store return data starting from pairingInput[0]
                    pairingInput,
                    // store 64 bytes of return data, i.e. overwrite pairingInput[0] & pairingInput[1] with the return data
                    0x40
                )
            ) {
                // revert if the call to the precompile failed
                revert(0, 0)
            }
        }
        //store pi (proof)
        pairingInput[2] = pi[0];
        pairingInput[3] = pi[1];
        pairingInput[4] = pi[2];
        pairingInput[5] = pi[3];
        //calculate c - [s]_1
        pairingInput[6] = c[0];
        pairingInput[7] = c[1];
        pairingInput[8] = 1;
        pairingInput[9] = MODULUS - 2;
        pairingInput[10] = s;

        //calculate -g1*s and store in slots '8' and '9' of input      -g1 = (1, -2) btw
        assembly {
            // @dev using precompiled contract at 0x07 to do G1 scalar multiplication on elliptic curve alt_bn128

            // multiply alt_bn128 point defined by (pairingInput[8], pairingInput[9]) by the scalar number pairingInput[10]
            if iszero(
                call(
                    // forward all gas
                    not(0),
                    // call ecMul precompile
                    0x07,
                    // send no value
                    0,
                    // send args starting from pairingInput[8]
                    add(pairingInput, 0x100),
                    // send 96 bytes of arguments, i.e. pairingInput[8], pairingInput[9], and pairingInput[10]
                    0x60,
                    // store return data starting at pairingInput[8]
                    add(pairingInput, 0x100),
                    // store 64 bytes of return data, i.e. overwrite pairingInput[8] & pairingInput[9] with the return data
                    0x40
                )
            ) {
                // revert if the call to the precompile failed
                revert(0, 0)
            }

            // add together the alt_bn128 points defined by (pairingInput[6], pairingInput[7]) and (pairingInput[8], pairingInput[9])
            if iszero(
                call(
                    // forward all gas
                    not(0),
                    // call ecAdd precompile
                    0x06,
                    // send no value
                    0,
                    // send args starting from pairingInput[6]
                    add(pairingInput, 0x0C0),
                    // send 128 bytes of arguments, i.e. pairingInput[6], pairingInput[7], pairingInput[8], and pairingInput[9]
                    0x80,
                    // store return data starting from pairingInput[6]
                    add(pairingInput, 0x0C0),
                    // store 64 bytes of return data, i.e. overwrite pairingInput[6] & pairingInput[7] with the return data
                    0x40
                )
            ) {
                // revert if the call to the precompile failed
                revert(0, 0)
            }
        }

        //check e(z, pi)e(C-[s]_1, -g2) = 1
        assembly {
            // store -g2, where g2 is the negation of the generator of group G2
            // point gets stored in slots pairingInput[8] through (including) pairingInput[11]
            // note that the free memory pointer is not updated, so we should not do additional memory allocation after this assembly block
            mstore(add(pairingInput, 0x100), nG2x1)
            mstore(add(pairingInput, 0x120), nG2x0)
            mstore(add(pairingInput, 0x140), nG2y1)
            mstore(add(pairingInput, 0x160), nG2y0)

            // call the precompiled ec2 pairing contract at 0x08
            if iszero(
                call(
                    // forward all gas
                    not(0),
                    // call ecPairing precompile
                    0x08,
                    // send no value
                    0,
                    // send args starting from pairingInput[0]
                    pairingInput,
                    // send 384 byes of arguments, i.e. pairingInput[0] through (including) pairingInput[11]
                    0x180,
                    // store return data starting from pairingInput[0]
                    pairingInput,
                    // store 32 bytes of return data, i.e. overwrite pairingInput[0] with the return data
                    0x20
                )
            ) {
                // revert if the call to the precompile failed
                revert(0, 0)
            }
        }
        // check whether the call to the ecPairing precompile was successful (returns 1 if correct pairing, 0 otherwise)
        return pairingInput[0] == 1;
    }
}
