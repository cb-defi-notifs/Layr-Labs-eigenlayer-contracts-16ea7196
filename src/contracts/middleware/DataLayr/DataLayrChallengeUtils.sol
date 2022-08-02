// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrServiceManager.sol";
import "../../libraries/Merkle.sol";
import "../../libraries/BN254_Constants.sol";

contract DataLayrChallengeUtils {

    constructor() {}

    // makes sure that operatorPubkeyHash was *excluded* from set of non-signers
    // reverts if the operator is in the non-signer set
    function checkExclusionFromNonSignerSet(
        bytes32 operatorPubkeyHash,
        uint256 nonSignerIndex,
        IDataLayrServiceManager.SignatoryRecordMinusDataStoreId calldata signatoryRecord
    ) public pure {
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
                "DataLayrChallengeUtils.checkExclusionFromNonSignerSet: Wrong greater index"
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
                    "DataLayrChallengeUtils.checkExclusionFromNonSignerSet: Wrong lower index"
                );
            }
        }
    }

    // makes sure that operatorPubkeyHash was *included* in set of non-signers
    // reverts if the operator is *not* in the non-signer set
    function checkInclusionInNonSignerSet(
        bytes32 operatorPubkeyHash,
        uint256 nonSignerIndex,
        IDataLayrServiceManager.SignatoryRecordMinusDataStoreId calldata signatoryRecord
    ) public pure {
        require(
            operatorPubkeyHash == signatoryRecord.nonSignerPubkeyHashes[nonSignerIndex],
            "DataLayrChallengeUtils.checkInclusionInNonSignerSet: operator not included in non-signer set"
        );
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
            revert("DataLayrChallengeUtils.getLeadingCosetIndexFromHighestRootOfUnity: Cannot create number of frame higher than possible");
        }
        revert("DataLayrChallengeUtils.getLeadingCosetIndexFromHighestRootOfUnity: Cannot create number of frame higher than possible");
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
        require(n > 0, "DataLayrChallengeUtils.log2: Log must be defined");
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
    function getZeroPolyMerkleRoot(uint256 degree) public pure returns (bytes32) {
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
            revert("DataLayrChallengeUtils.getZeroPolyMerkleRoot: Log not in valid range");
        }
    }

    // opens up kzg commitment c(x) at r and makes sure c(r) = s. proof (pi) is in G2 to allow for calculation of Z in G1
    function openPolynomialAtPoint(uint256[2] memory c, uint256[4] calldata pi, uint256 r, uint256 s) public view returns(bool) {
        uint256[12] memory pairingInput;
        //calculate -g1*r and store in first 2 slots of input      -g1 = (1, -2) btw
        pairingInput[0] = 1;
        pairingInput[1] = MODULUS - 2;
        pairingInput[2] = r;
        assembly {
            // @dev using precompiled contract at 0x07 to do G1 scalar multiplication on elliptic curve alt_bn128

            if iszero(
                staticcall(
                    // forward all gas
                    not(0),
                    // call ecMul precompile
                    0x07,
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
                staticcall(
                    // forward all gas
                    not(0),
                    // call ecAdd precompile
                    0x06,
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
                staticcall(
                    // forward all gas
                    not(0),
                    // call ecMul precompile
                    0x07,
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
                staticcall(
                    // forward all gas
                    not(0),
                    // call ecAdd precompile
                    0x06,
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

        // store -g2, where g2 is the negation of the generator of group G2
        pairingInput[8] = nG2x1;
        pairingInput[9] = nG2x0;
        pairingInput[10] = nG2y1;
        pairingInput[11] = nG2y0;

        //check e(z, pi)e(C-[s]_1, -g2) = 1
        assembly {
            // call the precompiled ec2 pairing contract at 0x08
            if iszero(
                staticcall(
                    // forward all gas
                    not(0),
                    // call ecPairing precompile
                    0x08,
                    // send args starting from pairingInput[0]
                    pairingInput,
                    // send 384 byes of arguments, i.e. pairingInput[0] through (including) pairingInput[11]
                    0x180,
                    // store return data starting from pairingInput[12]
                    add(pairingInput, 0x160),
                    // store 32 bytes of return data, i.e. overwrite pairingInput[0] with the return data
                    0x20
                )
            ) {
                // revert if the call to the precompile failed
                revert(0, 0)
            }
        }
        // check whether the call to the ecPairing precompile was successful (returns 1 if correct pairing, 0 otherwise)
        return pairingInput[11] == 1;
    }

    function validateDisclosureResponse(
        uint256 chunkNumber,
        bytes calldata header,
        uint256[4] calldata multireveal,
        uint256[4] memory zeroPoly,
        bytes calldata zeroPolyProof
    ) public view returns(uint48) {
        (
            uint256[2] memory c,
            uint48 degree,
            uint32 numSys,
            uint32 numPar
        ) = getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(
                header
            );

        // check that [zeroPoly.x0, zeroPoly.x1, zeroPoly.y0, zeroPoly.y1] is actually the "chunkNumber" leaf
        // of the zero polynomial Merkle tree

        {
            //deterministic assignment of "y" here
            // @todo
            require(
                Merkle.checkMembership(
                    // leaf
                    keccak256(
                        abi.encodePacked(
                            zeroPoly[0],
                            zeroPoly[1],
                            zeroPoly[2],
                            zeroPoly[3]
                        )
                    ),
                    // index in the Merkle tree
                    getLeadingCosetIndexFromHighestRootOfUnity(
                        uint32(chunkNumber),
                        numSys,
                        numPar
                    ),
                    // Merkle root hash
                    getZeroPolyMerkleRoot(degree),
                    // Merkle proof
                    zeroPolyProof
                ),
                "Incorrect zero poly merkle proof"
            );
        }

        /**
         Doing pairing verification  e(Pi(s), Z_k(s)).e(C - I, -g2) == 1
         */
        //get the commitment to the zero polynomial of multireveal degree

        uint256[13] memory pairingInput;
        // extract the proof [Pi(s).x, Pi(s).y]
        (pairingInput[0], pairingInput[1]) = (multireveal[0], multireveal[1]);
        // extract the commitment to the zero polynomial: [Z_k(s).x0, Z_k(s).x1, Z_k(s).y0, Z_k(s).y1]
        (pairingInput[2], pairingInput[3], pairingInput[4], pairingInput[5])
            = (zeroPoly[1], zeroPoly[0], zeroPoly[3], zeroPoly[2]);
        // extract the polynomial that was committed to by the disperser while initDataStore [C.x, C.y]
        (pairingInput[6], pairingInput[7]) = (c[0], c[1]);
        // extract the commitment to the interpolating polynomial [I_k(s).x, I_k(s).y] and then negate it
        // to get [I_k(s).x, -I_k(s).y]
        pairingInput[8] = multireveal[2];
        // obtain -I_k(s).y        
        pairingInput[9] = (MODULUS - multireveal[3]) % MODULUS;

        assembly {
            // overwrite C(s) with C(s) - I(s)

            // @dev using precompiled contract at 0x06 to do point addition on elliptic curve alt_bn128

            if iszero(
                staticcall(
                    not(0),
                    0x06,
                    add(pairingInput, 0xC0),
                    0x80,
                    add(pairingInput, 0xC0),
                    0x40
                )
            ) {
                revert(0, 0)
            }
        }

        // store -g2, where g2 is the negation of the generator of group G2
        pairingInput[8] = nG2x1;
        pairingInput[9] = nG2x0;
        pairingInput[10] = nG2y1;
        pairingInput[11] = nG2y0;

        // check e(pi, z)e(C - I, -g2) == 1
        assembly {
            // call the precompiled ec2 pairing contract at 0x08
            if iszero(
                // call ecPairing precompile with 384 bytes of data,
                // i.e. input[0] through (including) input[11], and get 32 bytes of return data
                staticcall(
                    not(0),
                    0x08,
                    pairingInput,
                    0x180,
                    add(pairingInput, 0x160),
                    0x20
                )
            ) {
                revert(0, 0)
            }
        }

        require(pairingInput[11] == 1, "Pairing unsuccessful");
        return degree;
    }

    function nonInteractivePolynomialProof(
        uint256 chunkNumber,
        bytes calldata header,
        uint256[4] calldata multireveal,
        bytes calldata poly,
        uint256[4] memory zeroPoly,
        bytes calldata zeroPolyProof,
        uint256[4] calldata pi
    ) public view returns(bool) {

        (
            uint256[2] memory c,
            ,
            ,
        ) = getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(
                header
            );

        //verify pairing for the commitment to interpolating polynomial
        uint48 degree = validateDisclosureResponse(
            chunkNumber, 
            header, 
            multireveal,
            zeroPoly, 
            zeroPolyProof
        );
       
       // TODO: verify that this check is correct!
       // check that degree of polynomial in the header matches the length of the submitted polynomial
       // i.e. make sure submitted polynomial doesn't contain extra points
       require(
           (degree + 1) * 32 == poly.length,
           "Polynomial must have a 256 bit coefficient for each term"
       );

        //Calculating r, the point at which to evaluate the interpolating polynomial
        //using FS transform, we use keccak(poly, kzg.commit(poly)) to make the randomness intrisic to the solution
        uint256 r = uint256(keccak256(abi.encodePacked(poly, multireveal[2], multireveal[3]))) % MODULUS;
        uint256 s = linearPolynomialEvaluation(poly, r);
        bool res = openPolynomialAtPoint(c, pi, r, s); 

        if (res){
            return true;
        }
        return false;

    }

    //evaluates the given polynomial "poly" at value "r" and returns the result
    function linearPolynomialEvaluation(
        bytes calldata poly,
        uint256 r
    ) public pure returns(uint256){
        uint256 sum;
        uint256 length = poly.length/32;
        uint256 rPower = 1;
        for (uint i = 0; i < length; ) {
            uint256 coefficient = uint256(bytes32(poly[i:i+32]));
            sum = addmod(sum, mulmod(coefficient, rPower, MODULUS), MODULUS);
            rPower = mulmod(rPower, r, MODULUS);
            i += 32;
        }   
        return sum; 
    }
}
