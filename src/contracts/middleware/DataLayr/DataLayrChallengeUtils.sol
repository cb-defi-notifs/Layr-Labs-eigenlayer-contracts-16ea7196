// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrServiceManager.sol";
import "../../libraries/Merkle.sol";
import "../../libraries/BN254.sol";
import "../../libraries/BN254_Constants.sol";

contract DataLayrChallengeUtils {

    struct MultiRevealProof {
        BN254.G1Point interpolationPoly;
        BN254.G1Point revealProof;
        BN254.G2Point zeroPoly;
        bytes zeroPolyProof;
    }

    struct DataStoreKZGMetadata {
        BN254.G1Point c;
        uint48 degree;
        uint32 numSys;
        uint32 numPar;
    }

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

    // makes sure that operatorPubkeyHash was *included* in set of non-signers
    // reverts if the operator is *not* in the non-signer set
    function checkInclusionInNonSignerSet(
        bytes32 operatorPubkeyHash,
        uint256 nonSignerIndex,
        IDataLayrServiceManager.SignatoryRecordMinusDataStoreId calldata signatoryRecord
    ) public pure {
        require(
            operatorPubkeyHash == signatoryRecord.nonSignerPubkeyHashes[nonSignerIndex],
            "operator not included in non-signer set"
        );
    }

    function getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(
        // bytes calldata header
        bytes calldata
    )
        public
        pure
        returns (
            DataStoreKZGMetadata memory
        )
    {
        // return x, y coordinate of overall data poly commitment
        // then return degree of multireveal polynomial
        BN254.G1Point memory point;
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

        return DataStoreKZGMetadata({c: point, degree: degree, numSys: numSys, numPar: numPar});
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
            revert("Log not in valid range");
        }
    }

    // opens up kzg commitment c(x) at r and makes sure c(r) = s. proof (pi) is in G2 to allow for calculation of Z in G1
    function openPolynomialAtPoint(BN254.G1Point memory c, BN254.G2Point calldata pi, uint256 r, uint256 s) public view returns(bool) {
        //we use and overwrite z as temporary storage
        //-g1 = (1, -2)
        BN254.G1Point memory negativeOne = BN254.G1Point({X: 1, Y: BN254_Constants.MODULUS - 2});
        //calculate -g1*r = -[r]_1
        BN254.G1Point memory z = BN254.scalar_mul(negativeOne, r);

        //add [x]_1 - [r]_1 = Z and store in first 2 slots of input
        //CRITIC TODO: SWITCH THESE TO [x]_1 of Powers of Tau!
        BN254.G1Point memory firstPowerOfTau = BN254.G1Point({X: 1, Y: BN254_Constants.MODULUS - 2});
        z = BN254.plus(firstPowerOfTau, z);
        //calculate -g1*s = -[s]_1
        BN254.G1Point memory negativeS = BN254.scalar_mul(negativeOne, s);
        //calculate C-[s]_1
        BN254.G1Point memory cMinusS = BN254.plus(c, negativeS);
        //-g2
        BN254.G2Point memory negativeG2 = BN254.G2Point({X: [BN254_Constants.nG2x1, BN254_Constants.nG2x0], Y: [BN254_Constants.nG2y1, BN254_Constants.nG2y0]});

        //check e(z, pi)e(C-[s]_1, -g2) = 1
        return BN254.pairing(z, pi, cMinusS, negativeG2);
    }

    function validateDisclosureResponse(
        DataStoreKZGMetadata memory dskzgMetadata,
        uint32 chunkNumber,
        BN254.G1Point calldata interpolationPoly,
        BN254.G1Point calldata revealProof,
        BN254.G2Point memory zeroPoly,
        bytes calldata zeroPolyProof
    ) public view returns(bool) {
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
                            zeroPoly.X[0],
                            zeroPoly.X[1],
                            zeroPoly.Y[0],
                            zeroPoly.Y[1]
                        )
                    ),
                    // index in the Merkle tree
                    getLeadingCosetIndexFromHighestRootOfUnity(
                        chunkNumber,
                        dskzgMetadata.numSys,
                        dskzgMetadata.numPar
                    ),
                    // Merkle root hash
                    getZeroPolyMerkleRoot(dskzgMetadata.degree),
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

        // calculate [C]_1 - [I]_1
        BN254.G1Point memory cMinusI = BN254.plus(dskzgMetadata.c, BN254.negate(interpolationPoly));
        //-g2
        BN254.G2Point memory negativeG2 = BN254.G2Point({X: [BN254_Constants.nG2x1, BN254_Constants.nG2x0], Y: [BN254_Constants.nG2y1, BN254_Constants.nG2y0]});

        //check e(z, pi)e(C-[s]_1, -g2) = 1
        return BN254.pairing(revealProof, zeroPoly, cMinusI, negativeG2);
    }

    function nonInteractivePolynomialProof(
        bytes calldata header,
        uint32 chunkNumber,
        bytes calldata poly,
        MultiRevealProof calldata multiRevealProof,
        BN254.G2Point calldata polyEquivalenceProof
    ) public view returns(bool) {
        DataStoreKZGMetadata memory dskzgMetadata = getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(
                header
            );

        //verify pairing for the commitment to interpolating polynomial
        require(validateDisclosureResponse(
            dskzgMetadata,
            chunkNumber, 
            multiRevealProof.interpolationPoly,
            multiRevealProof.revealProof,
            multiRevealProof.zeroPoly, 
            multiRevealProof.zeroPolyProof
        ), "Reveal failed due to non 1 pairing");
       
       // TODO: verify that this check is correct!
       // check that degree of polynomial in the header matches the length of the submitted polynomial
       // i.e. make sure submitted polynomial doesn't contain extra points
       require(
           (dskzgMetadata.degree + 1) * 32 == poly.length,
           "Polynomial must have a 256 bit coefficient for each term"
       );

        //Calculating r, the point at which to evaluate the interpolating polynomial
        uint256 r = uint256(keccak256(abi.encodePacked(keccak256(poly), multiRevealProof.interpolationPoly.X, multiRevealProof.interpolationPoly.Y))) % BN254_Constants.MODULUS;
        uint256 s = linearPolynomialEvaluation(poly, r);
        bool ok = openPolynomialAtPoint(multiRevealProof.interpolationPoly, polyEquivalenceProof, r, s); 
        return ok;
    }

    //this function allows senders to reveal many chunks starting from `firstChunkNumber` in series on the polynomial
    //the main benefit of using this function versus repeatedly calling nonInteractivePolynomialProof is there
    //is an ecMul per poly and 1 pairing TOTAL as opposed to 1 pairing per poly. described in section 3.1 of https://eprint.iacr.org/2019/953.pdf
    function batchNonInteractivePolynomialProofs(
        bytes calldata header,
        uint32 firstChunkNumber,
        bytes[] calldata polys,
        MultiRevealProof[] calldata multiRevealProofs,
        BN254.G2Point calldata polyEquivalenceProof
    ) public view returns(bool) {
        //randomness from each polynomial
        bytes32[] memory rs = new bytes32[](polys.length);
        DataStoreKZGMetadata memory dskzgMetadata = getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(
                header
            );
        uint256 numProofs = multiRevealProofs.length;
        for(uint256 i = 0; i < numProofs;) {
            //verify pairing for the commitment to interpolating polynomial
            require(validateDisclosureResponse(
                dskzgMetadata,
                firstChunkNumber + uint32(i), 
                multiRevealProofs[i].interpolationPoly,
                multiRevealProofs[i].revealProof,
                multiRevealProofs[i].zeroPoly, 
                multiRevealProofs[i].zeroPolyProof
            ), "Reveal failed due to non 1 pairing");
        
            // TODO: verify that this check is correct!
            // check that degree of polynomial in the header matches the length of the submitted polynomial
            // i.e. make sure submitted polynomial doesn't contain extra points
            require(
                (dskzgMetadata.degree + 1) * 32 == polys[i].length,
                "Polynomial must have a 256 bit coefficient for each term"
            );

            //Calculating r, the point at which to evaluate the interpolating polynomial
            rs[i] = keccak256(abi.encodePacked(keccak256(polys[i]), multiRevealProofs[i].interpolationPoly.X, multiRevealProofs[i].interpolationPoly.Y));
            unchecked {
                ++i;
            }
        }
        //this is the point to open each polynomial at
        uint256 r = uint256(keccak256(abi.encodePacked(rs))) % BN254_Constants.MODULUS;
        //this is the offset we add to each polynomial to prevent collision
        //we use array to help with stack
        uint256[2] memory gammaAndGammaPower;
        gammaAndGammaPower[0] = uint256(keccak256(abi.encodePacked(rs, uint256(0)))) % BN254_Constants.MODULUS;
        gammaAndGammaPower[1] = gammaAndGammaPower[0];
        //store I1
        BN254.G1Point memory gammaShiftedCommitmentSum = multiRevealProofs[0].interpolationPoly;
        //store I1(r)
        uint256 gammaShiftedEvaluationSum = linearPolynomialEvaluation(polys[0], r);
        for (uint i = 1; i < multiRevealProofs.length; i++) {
            //gammaShiftedCommitmentSum += gamma^i * Ii
            gammaShiftedCommitmentSum = BN254.plus(gammaShiftedCommitmentSum, BN254.scalar_mul(multiRevealProofs[i].interpolationPoly, gammaAndGammaPower[1]));
            //gammaShiftedEvaluationSum += gamma^i * Ii(r)
            uint256 eval = linearPolynomialEvaluation(polys[i], r);
            gammaShiftedEvaluationSum = (gammaShiftedEvaluationSum + ((gammaAndGammaPower[1]*eval) % BN254_Constants.MODULUS) % BN254_Constants.MODULUS);
            // gammaPower = gamma^(i+1)
            gammaAndGammaPower[1] = mulmod(gammaAndGammaPower[0], gammaAndGammaPower[1], BN254_Constants.MODULUS);
        }

        return openPolynomialAtPoint(gammaShiftedCommitmentSum, polyEquivalenceProof, r, gammaShiftedEvaluationSum);
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
            sum = addmod(sum, mulmod(coefficient, rPower, BN254_Constants.MODULUS), BN254_Constants.MODULUS);
            rPower = mulmod(rPower, r, BN254_Constants.MODULUS);
            i += 32;
        }   
        return sum; 
    }
}
