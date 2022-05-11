// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./DataLayrServiceManagerStorage.sol";
import "../RegistrationManagerBaseMinusRepository.sol";
import "../../libraries/BytesLib.sol";
import "../../libraries/SignatureCompaction.sol";

import "ds-test/test.sol";




/**
 @notice This is the contract for checking that the aggregated signatures of all DataLayr operators which is being 
         asserted by the disperser is valid.
 */
abstract contract DataLayrSignatureChecker is
    DataLayrServiceManagerStorage,
    DSTest
{
    using BytesLib for bytes;

    // CONSTANTS
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




    // DATA STRUCTURES
    /**
     @notice this data structure is used for recording the details on the total stake of the registered
             DataLayr operators and those operators who are part of the quorum for a particular dumpNumber
     */
    struct SignatoryTotals {
        // total ETH stake of the DataLayr operators who are in the quorum
        uint256 ethStakeSigned;
        // total Eigen stake of the DataLayr operators who are in the quorum
        uint256 eigenStakeSigned;
        // total ETH staked by all DataLayr operators (irrespective of whether they are in quorum or not)
        uint256 totalEthStake;
        // total Eigen staked by all DataLayr operators (irrespective of whether they are in quorum or not)
        uint256 totalEigenStake;
    }

    // EVENTS
    /**
     @notice used for recording the event that signature has been checked in checkSignatures function.
     */
    event SignatoryRecord(
        bytes32 headerHash,
        uint32 dumpNumber,
        uint256 ethStakeSigned,
        uint256 eigenStakeSigned,
        bytes32[] pubkeyHashes
    );



    /**
     @notice This function is called by disperser when it has aggregated all the signatures of the DataLayr operators
             that are part of the quorum for a particular dumpNumber and is asserting them into on-chain. The function 
             checks that the claim for aggergated signatures are valid.

             The thesis of this procedure entails:
              - computing the aggregated pubkey of all the DataLayr operators that are not part of the quorum for 
                this specific dumpNumber (represented by aggNonSignerPubkey)
              - getting the aggregated pubkey of all registered DataLayr nodes at the time of pre-commit by the 
                disperser (represented by pk),
              - do subtraction of aggNonSignerPubkey from pk over Jacobian coordinate system to get aggregated pubkey
                of all DataLayr operators that are part of quorum.
              - use this aggregated pubkey to verify the aggregated signature under BLS scheme.
     */
    /** 
     @param data This calldata is of the format:
            <
             uint32 dumpNumber,
             bytes32 headerHash,
             uint48 index of the totalStake corresponding to the dumpNumber in the 'totalStakeHistory' array of the DataLayrRegistry
             uint32 numberOfNonSigners,
             uint256[numberOfSigners][4] pubkeys of nonsigners,
             uint32 apkIndex,
             uint256[4] apk,
             uint256[2] sigma
            >
     */
    //NOTE: this assumes length 64 signatures
    function checkSignatures(bytes calldata data)
        public
        returns (
            uint32 dumpNumberToConfirm,
            bytes32 headerHash,
            SignatoryTotals memory signedTotals,
            bytes32 compressedSignatoryRecord
        )
    {
        //dumpNumber corresponding to the headerHash
        //number of different signature bins that signatures are being posted from
        uint256 placeholder;

        assembly {
            // get the 4 bytes immediately after the function signature and length encoding of bytes
            // calldata type, which would represent the dump number at the time of pre-commit for which
            // disperser is calling checkSignatures.
            dumpNumberToConfirm := shr(224, calldataload(68))

            // get the 32 bytes immediately after the above
            headerHash := calldataload(72)

            // get the 6 bytes immediately after the above, which would represent the
            // index of the totalStake in the 'totalStakeHistory' array
            placeholder := shr(208, calldataload(104))
        }

        // we have read (68 + 4 + 32 + 4 + 6) = 114 bytes of calldata
        uint256 pointer = 114;


        // obtain DataLayr's voteweigher contract for querying information on stake later
        IDataLayrRegistry dlRegistry = IDataLayrRegistry(address(repository.voteWeigher()));


        // to be used for holding the aggregated pub key of all DataLayr operators
        // that aren't part of the quorum
        /**
         @dev we would be storing points in G2 using Jacobian coordinates - [x0, x1, y0, y1, z0, z1]
         */
        uint256[6] memory aggNonSignerPubkey;


        // get information on total stakes
        SignatoryTotals memory sigTotals;
        IDataLayrRegistry.OperatorStake memory totalStake = dlRegistry.getTotalStakeFromIndex(placeholder);

        // check that the stake returned from the specified index is recent enough
        require(
            totalStake.dumpNumber <= dumpNumberToConfirm,
            "Total stake index is too early"
        );

        /** 
          check that stake is either the most recent update for the total stake, 
          or latest before the dumpNumberToConfirm
         */
        require(
            totalStake.nextUpdateDumpNumber == 0 ||
                totalStake.nextUpdateDumpNumber > dumpNumberToConfirm,
            "Total stake index is too early"
        );

        signedTotals.ethStakeSigned = totalStake.ethStake;
        signedTotals.totalEthStake = signedTotals.ethStakeSigned;
        signedTotals.eigenStakeSigned = totalStake.eigenStake;
        signedTotals.totalEigenStake = signedTotals.eigenStakeSigned;

        assembly {
            // get the 4 bytes immediately after the above, which would represent the
            // number of DataLayr operators that aren't present in the quorum
            placeholder := shr(224, calldataload(110))
        }

        // to be used for holding the pub key hashes of the DataLayr operators that aren't part of the quorum
        bytes32[] memory pubkeyHashes = new bytes32[](placeholder);
        emit log("stupid");

        /**
         @notice next step involves computing the aggregated pub key of all the DataLayr operators
                 that are not part of the quorum for this specific dumpNumber. 
         */
        /**
         @dev loading pubkey for the first DataLayr operator that is not part of the quorum as listed in the calldata; 
              Note that this need not be a special case and can be subsumed in the for loop below.    
         */
        if (placeholder > 0) {
            uint256 stakeIndex;

            assembly {
                /** 
                 @notice retrieving the pubkey of the DataLayr node in Jacobian coordinates
                 */
                // sigma_x0
                mstore(aggNonSignerPubkey, calldataload(pointer))

                // sigma_x1
                mstore(
                    add(aggNonSignerPubkey, 0x20),
                    calldataload(add(pointer, 32))
                )

                // sigma_y0
                mstore(
                    add(aggNonSignerPubkey, 0x40),
                    calldataload(add(pointer, 64))
                )

                // sigma_y1
                mstore(
                    add(aggNonSignerPubkey, 0x60),
                    calldataload(add(pointer, 96))
                )

                // converting Affine coordinates to Jacobian coordinates
                // [(x_0, x_1), (y_0, y_1)] => [(x_0, x_1), (y_0, y_1), (1,0)]
                // source: https://crypto.stackexchange.com/questions/19598/how-can-convert-affine-to-jacobian-coordinates
                // sigma_z0
                mstore(add(aggNonSignerPubkey, 0x80), 1)
                // sigma_z1
                mstore(add(aggNonSignerPubkey, 0xA0), 0)

                /** 
                 @notice retrieving the index of the stake of the DataLayr operator in pubkeyHashToStakeHistory in 
                         DataLayrRegistry.sol that was recorded at the time of pre-commit.
                 */
                stakeIndex := shr(224, calldataload(add(pointer, 128)))
            }

            // We have read (32 + 32 + 32 + 32 + 4) = 132 bytes of calldata above.
            // Update pointer.
            pointer += 132;

            // get pubkeyHash and add it to pubkeyHashes of DataLayr operators that aren't part of the quorum.
            bytes32 pubkeyHash = keccak256(
                abi.encodePacked(
                    aggNonSignerPubkey[0],
                    aggNonSignerPubkey[1],
                    aggNonSignerPubkey[2],
                    aggNonSignerPubkey[3]
                )
            );
            pubkeyHashes[0] = pubkeyHash;

            // querying the VoteWeigher for getting information on the DataLayr operator's stake
            // at the time of pre-commit
            IDataLayrRegistry.OperatorStake memory operatorStake = dlRegistry
                .getStakeFromPubkeyHashAndIndex(pubkeyHash, stakeIndex);

            // check that the stake returned from the specified index is recent enough
            require(
                operatorStake.dumpNumber <= dumpNumberToConfirm,
                "Operator stake index is too early"
            );

            /** 
              check that stake is either the most recent update for the operator, 
              or latest before the dumpNumberToConfirm
             */
            require(
                operatorStake.nextUpdateDumpNumber == 0 ||
                    operatorStake.nextUpdateDumpNumber > dumpNumberToConfirm,
                "Operator stake index is too early"
            );

            // subtract operator stakes from totals
            signedTotals.ethStakeSigned -= operatorStake.ethStake;
            signedTotals.eigenStakeSigned -= operatorStake.eigenStake;
        }

        // temporary variable for storing the pubkey of DataLayr operators in Jacobian coordinates
        uint256[6] memory pk;
        pk[4] = 1;

        emit log_uint(placeholder);

        for (uint i = 1; i < placeholder; ) {
            //load compressed pubkey into memory and the index in the stakes array
            uint256 stakeIndex;

            assembly {
                /// @notice retrieving the pubkey of the DataLayr operator that is not part of the quorum
                mstore(pk, calldataload(pointer))
                mstore(add(pk, 0x20), calldataload(add(pointer, 32)))
                mstore(add(pk, 0x40), calldataload(add(pointer, 64)))
                mstore(add(pk, 0x60), calldataload(add(pointer, 96)))

                /**
                 @notice retrieving the index of the stake of the DataLayr operator in pubkeyHashToStakeHistory in 
                         DataLayrRegistry.sol that was recorded at the time of pre-commit.
                 */
                stakeIndex := shr(224, calldataload(add(pointer, 128)))
            }


            // We have read (32 + 32 + 32 + 32 + 4) = 132 bytes of calldata above.
            // Update pointer.
            pointer += 132;


            // get pubkeyHash and add it to pubkeyHashes of DataLayr operators that aren't part of the quorum.
            bytes32 pubkeyHash = keccak256(
                abi.encodePacked(pk[0], pk[1], pk[2], pk[3])
            );


            //pubkeys should be ordered in scending order of hash to make proofs of signing or non signing constant time
            require(
                uint256(pubkeyHash) > uint256(pubkeyHashes[i - 1]),
                "Pubkey hashes must be in ascending order"
            );


            // recording the pubkey hash
            pubkeyHashes[i] = pubkeyHash;


            // querying the VoteWeigher for getting information on the DataLayr operator's stake
            // at the time of pre-commit
            IDataLayrRegistry.OperatorStake memory operatorStake = dlRegistry.getStakeFromPubkeyHashAndIndex(pubkeyHash, stakeIndex);


            // check that the stake returned from the specified index is recent enough
            require(
                operatorStake.dumpNumber <= dumpNumberToConfirm,
                "Operator stake index is too early"
            );


            // check that stake is either the most recent update for the operator, or latest before the dupNumberToConfirm
            require(
                operatorStake.nextUpdateDumpNumber == 0 ||
                    operatorStake.nextUpdateDumpNumber > dumpNumberToConfirm,
                "Operator stake index is too early"
            );


            //subtract validator stakes from totals
            signedTotals.ethStakeSigned -= operatorStake.ethStake;
            signedTotals.eigenStakeSigned -= operatorStake.eigenStake;

            // add the pubkey of the DataLayr operator to the aggregate pubkeys in Jacobian coordinate system.
            addJac(aggNonSignerPubkey, pk);

            
            unchecked {
                ++i;
            }
        }

        assembly {
            //get next 32 bits which would be the apkIndex of apkUpdates in DataLayrRegistry.sol
            placeholder := shr(224, calldataload(pointer))

            // get the aggregated publickey at the moment when pre-commit happened
            /**
             @dev aggregated pubkey given as part of calldata instead of being retrieved from voteWeigher is 
                  in order to avoid SLOADs  
             */
            mstore(pk, calldataload(add(pointer, 4)))
            mstore(add(pk, 0x20), calldataload(add(pointer, 36)))
            mstore(add(pk, 0x40), calldataload(add(pointer, 68)))
            mstore(add(pk, 0x60), calldataload(add(pointer, 100)))
        }

        // We have read (4 + 32 + 32 + 32 + 32) = 132 bytes of calldata above.
        // Update pointer.
        pointer += 132;


        // make sure they have provided the correct aggPubKey
        require(
            dlRegistry.getCorrectApkHash(placeholder, dumpNumberToConfirm) == keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3])),
            "Incorrect apk provided"
        );


        // input for call to ecPairing precomplied contract
        uint256[12] memory input = [
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0)
        ];

        assembly {
            // get the 4 bytes immediately after the above, which would represent the
            // number of DataLayr operators that aren't present in the quorum
            placeholder := shr(224, calldataload(104))
        }

        if (placeholder != 0) {
            /**
             @notice need to subtract aggNonSignerPubkey from the apk to get aggregate signature of all
                     DataLayr operators that are part of the quorum   
             */
            // negate aggNonSignerPubkey
            aggNonSignerPubkey[2] = (MODULUS - aggNonSignerPubkey[2]) % MODULUS;
            aggNonSignerPubkey[3] = (MODULUS - aggNonSignerPubkey[3]) % MODULUS;

            // do the addition in Jacobian coordinates
            addJac(pk, aggNonSignerPubkey);

            // reorder for pairing
            (input[3], input[2], input[5], input[4]) = jacToAff(pk);
        } else {
            //else copy it to input
            //reorder for pairing
            (input[3], input[2], input[5], input[4]) = (
                pk[0],
                pk[1],
                pk[2],
                pk[3]
            );
        }

        /**
         @notice now we verify that e(H(m), pk)e(sigma, -g2) == 1
         */

        // compute the point in G1 
        (input[0], input[1]) = hashToG1(headerHash);

        // insert negated coordinates of the generator for G2
        input[8] = nG2x1;
        input[9] = nG2x0;
        input[10] = nG2y1;
        input[11] = nG2y0;

        assembly {
            // next in calldata are the signatures
            // sigma_x0
            mstore(add(input, 0xC0), calldataload(pointer))
            // sigma_x1
            mstore(add(input, 0xE0), calldataload(add(pointer, 0x20)))

            // check the pairing; if incorrect, revert
            if iszero(call(not(0), 0x08, 0, input, 0x0180, input, 0x20)) {
                revert(0, 0)
            }
        }

        // check that signature is correct
        require(input[0] == 1, "Pairing unsuccessful");

        

        emit SignatoryRecord(
            headerHash,
            dumpNumberToConfirm,
            signedTotals.ethStakeSigned,
            signedTotals.eigenStakeSigned,
            pubkeyHashes
        );

        // set compressedSignatoryRecord variable used for payment fraud proofs
        compressedSignatoryRecord = keccak256(
            abi.encodePacked(
                // headerHash,
                dumpNumberToConfirm,
                signedTotals.ethStakeSigned,
                signedTotals.eigenStakeSigned,
                pubkeyHashes
            )
        );

        // return dumpNumber, headerHash, eth and eigen that signed, and a hash of the signatories
        return (
            dumpNumberToConfirm,
            headerHash,
            signedTotals,
            compressedSignatoryRecord
        );
    }



    function addJac(uint256[6] memory jac1, uint256[6] memory jac2)
        internal
        pure
        returns (uint256[6] memory)
    {
        //NOTE: JAC IS REFERRED TO AS X, Y, Z
        //ALL 2 ELEMENTS EACH
        // var XX, YY, YYYY, ZZ, S, M, T fptower.E2

        if (jac1[4] == 0 && jac1[5] == 0) {
            return jac2;
        } else if (jac2[4] == 0 && jac2[5] == 0) {
            return jac1;
        }

        // var Z1Z1, Z2Z2, U1, U2, S1, S2, H, I, J, r, V fptower.E2
        //z1z1 = a.z^2
        uint256[4] memory z1z1z2z2;
        (z1z1z2z2[0], z1z1z2z2[1]) = square(jac2[4], jac2[5]);
        //z2z2 = p.z^2
        // uint256[2] memory z2z2;
        (z1z1z2z2[2], z1z1z2z2[3]) = square(jac1[4], jac1[5]);
        //u1 = a.x*z2z2
        uint256[4] memory u1u2;
        (u1u2[0], u1u2[1]) = mul(jac2[0], jac2[1], z1z1z2z2[2], z1z1z2z2[3]);
        //u2 = p.x*z1z1
        // uint256[2] memory u2;
        (u1u2[2], u1u2[3]) = mul(jac1[0], jac1[1], z1z1z2z2[0], z1z1z2z2[1]);
        //s1 = a.y*p.z*z2z2
        uint256[2] memory s1;
        (s1[0], s1[1]) = mul(jac2[2], jac2[3], jac1[4], jac1[5]);
        (s1[0], s1[1]) = mul(s1[0], s1[1], z1z1z2z2[2], z1z1z2z2[3]);

        //s2 = p.y*a.z*z1z1
        uint256[2] memory s2;
        (s2[0], s2[1]) = mul(jac1[2], jac1[3], jac2[4], jac2[5]);
        (s2[0], s2[1]) = mul(s2[0], s2[1], z1z1z2z2[0], z1z1z2z2[1]);

        // // if p == a, we double instead, is this too inefficient?
        // // if (u1[0] == 0 && u1[1] == 0 && u2[0] == 0 && u2[1] == 0) {
        // //     return p.DoubleAssign()
        // // } else {

        // // }

        uint256[2] memory h;
        uint256[2] memory i;

        assembly {
            //h = u2 - u1
            mstore(
                h,
                addmod(
                    mload(add(u1u2, 0x040)),
                    sub(MODULUS, mload(u1u2)),
                    MODULUS
                )
            )
            mstore(
                add(h, 0x20),
                addmod(
                    mload(add(u1u2, 0x60)),
                    sub(MODULUS, mload(add(u1u2, 0x20))),
                    MODULUS
                )
            )

            //i = 2h
            mstore(i, mulmod(mload(h), 2, MODULUS))
            mstore(add(i, 0x20), mulmod(mload(add(h, 0x20)), 2, MODULUS))
        }

        (i[0], i[1]) = square(i[0], i[1]);

        uint256[2] memory j;
        (j[0], j[1]) = mul(h[0], h[1], i[0], i[1]);

        uint256[2] memory r;
        assembly {
            //r = s2 - s1
            mstore(r, addmod(mload(s2), sub(MODULUS, mload(s1)), MODULUS))
            mstore(
                add(r, 0x20),
                addmod(
                    mload(add(s2, 0x20)),
                    sub(MODULUS, mload(add(s1, 0x20))),
                    MODULUS
                )
            )

            //r *= 2
            mstore(r, mulmod(mload(r), 2, MODULUS))
            mstore(add(r, 0x20), mulmod(mload(add(r, 0x20)), 2, MODULUS))
        }

        uint256[2] memory v;
        (v[0], v[1]) = mul(u1u2[0], u1u2[1], i[0], i[1]);

        (jac1[0], jac1[1]) = square(r[0], r[1]);

        assembly {
            //x -= j
            mstore(jac1, addmod(mload(jac1), sub(MODULUS, mload(j)), MODULUS))
            mstore(
                add(jac1, 0x20),
                addmod(
                    mload(add(jac1, 0x20)),
                    sub(MODULUS, mload(add(j, 0x20))),
                    MODULUS
                )
            )
            //x -= v
            mstore(jac1, addmod(mload(jac1), sub(MODULUS, mload(v)), MODULUS))
            mstore(
                add(jac1, 0x20),
                addmod(
                    mload(add(jac1, 0x20)),
                    sub(MODULUS, mload(add(v, 0x20))),
                    MODULUS
                )
            )
            //x -= v
            mstore(jac1, addmod(mload(jac1), sub(MODULUS, mload(v)), MODULUS))
            mstore(
                add(jac1, 0x20),
                addmod(
                    mload(add(jac1, 0x20)),
                    sub(MODULUS, mload(add(v, 0x20))),
                    MODULUS
                )
            )
            //y = v - x
            mstore(
                add(jac1, 0x40),
                addmod(mload(v), sub(MODULUS, mload(jac1)), MODULUS)
            )
            mstore(
                add(jac1, 0x60),
                addmod(
                    mload(add(v, 0x20)),
                    sub(MODULUS, mload(add(jac1, 0x20))),
                    MODULUS
                )
            )
        }

        (jac1[2], jac1[3]) = mul(jac1[2], jac1[3], r[0], r[1]);
        (s1[0], s1[1]) = mul(s1[0], s1[1], j[0], j[1]);

        assembly {
            //s1 *= 2
            mstore(s1, mulmod(mload(s1), 2, MODULUS))
            mstore(add(s1, 0x20), mulmod(mload(add(s1, 0x20)), 2, MODULUS))
            //y -= s1
            mstore(
                add(jac1, 0x40),
                addmod(mload(add(jac1, 0x40)), sub(MODULUS, mload(s1)), MODULUS)
            )
            mstore(
                add(jac1, 0x60),
                addmod(
                    mload(add(jac1, 0x60)),
                    sub(MODULUS, mload(add(s1, 0x20))),
                    MODULUS
                )
            )
            //z = a.z + p.z
            mstore(
                add(jac1, 0x80),
                addmod(mload(add(jac1, 0x80)), mload(add(jac2, 0x80)), MODULUS)
            )
            mstore(
                add(jac1, 0xA0),
                addmod(mload(add(jac1, 0xA0)), mload(add(jac2, 0xA0)), MODULUS)
            )
        }

        (jac1[4], jac1[5]) = square(jac1[4], jac1[5]);

        assembly {
            //z -= z1z1
            mstore(
                add(jac1, 0x80),
                addmod(
                    mload(add(jac1, 0x80)),
                    sub(MODULUS, mload(z1z1z2z2)),
                    MODULUS
                )
            )
            mstore(
                add(jac1, 0xA0),
                addmod(
                    mload(add(jac1, 0xA0)),
                    sub(MODULUS, mload(add(z1z1z2z2, 0x20))),
                    MODULUS
                )
            )
            //z -= z2z2
            mstore(
                add(jac1, 0x80),
                addmod(
                    mload(add(jac1, 0x80)),
                    sub(MODULUS, mload(add(z1z1z2z2, 0x40))),
                    MODULUS
                )
            )
            mstore(
                add(jac1, 0xA0),
                addmod(
                    mload(add(jac1, 0xA0)),
                    sub(MODULUS, mload(add(z1z1z2z2, 0x60))),
                    MODULUS
                )
            )
        }

        (jac1[4], jac1[5]) = mul(jac1[4], jac1[5], h[0], h[1]);

        return jac1;
    }

    function square(uint256 x0, uint256 x1)
        internal
        pure
        returns (uint256, uint256)
    {
        uint256[4] memory z;
        assembly {
            //a = x0 + x1
            mstore(z, addmod(x0, x1, MODULUS))
            //b = x0 - x1
            mstore(add(z, 0x20), addmod(x0, sub(MODULUS, x1), MODULUS))
            //a = (x0 + x1)(x0 - x1)
            mstore(add(z, 0x40), mulmod(mload(z), mload(add(z, 0x20)), MODULUS))
            //b = 2x0y0
            mstore(add(z, 0x60), mulmod(2, mulmod(x0, x1, MODULUS), MODULUS))
        }
        return (z[2], z[3]);
    }

    function jacToAff(uint256[6] memory jac)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        if (jac[4] == 0 && jac[5] == 0) {
            return (uint256(0), uint256(0), uint256(0), uint256(0));
        }

        (jac[4], jac[5]) = inverse(jac[4], jac[5]);
        (uint256 b0, uint256 b1) = square(jac[4], jac[5]);
        (jac[0], jac[1]) = mul(jac[0], jac[1], b0, b1);
        (jac[2], jac[3]) = mul(jac[2], jac[3], b0, b1);
        (jac[2], jac[3]) = mul(jac[2], jac[3], jac[4], jac[5]);

        return (jac[0], jac[1], jac[2], jac[3]);
    }

    function inverse(uint256 x0, uint256 x1)
        public
        view
        returns (uint256, uint256)
    {
        uint256[2] memory t;
        assembly {
            mstore(t, mulmod(x0, x0, MODULUS))
            mstore(add(t, 0x20), mulmod(x1, x1, MODULUS))
            mstore(t, addmod(mload(t), mload(add(t, 0x20)), MODULUS))

            let freemem := mload(0x40)
            mstore(freemem, 0x20)
            mstore(add(freemem, 0x20), 0x20)
            mstore(add(freemem, 0x40), 0x20)
            mstore(add(freemem, 0x60), mload(t))
            // x^(n-2) = x^-1 mod q
            mstore(add(freemem, 0x80), sub(MODULUS, 2))
            // N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            mstore(add(freemem, 0xA0), MODULUS)
            if iszero(
                staticcall(
                    sub(gas(), 2000),
                    5,
                    freemem,
                    0xC0,
                    add(t, 0x20),
                    0x20
                )
            ) {
                revert(0, 0)
            }
            mstore(t, mulmod(x0, mload(add(t, 0x20)), MODULUS))
            mstore(add(t, 0x20), mulmod(x1, mload(add(t, 0x20)), MODULUS))
        }

        return (t[0], MODULUS - t[1]);
    }

    function mul(
        uint256 x0,
        uint256 x1,
        uint256 y0,
        uint256 y1
    ) internal pure returns (uint256, uint256) {
        uint256[5] memory z;
        assembly {
            //a = x0 + x1
            mstore(z, addmod(x0, x1, MODULUS))
            //b = y0 + y1
            mstore(add(z, 0x20), addmod(y0, y1, MODULUS))
            //a = (x0 + x1)(y0 + y1)
            mstore(z, mulmod(mload(z), mload(add(z, 0x20)), MODULUS))
            //b = x0y0
            mstore(add(z, 0x20), mulmod(x0, y0, MODULUS))
            //c = x1y1
            mstore(add(z, 0x40), mulmod(x1, y1, MODULUS))
            //c = -x1y1
            mstore(add(z, 0x40), sub(MODULUS, mload(add(z, 0x40))))
            //z0 = x0y0 - x1y1
            mstore(
                add(z, 0x60),
                addmod(mload(add(z, 0x20)), mload(add(z, 0x40)), MODULUS)
            )
            //b = -x0y0
            mstore(add(z, 0x20), sub(MODULUS, mload(add(z, 0x20))))
            //z1 = x0y1 + x1y0
            mstore(
                add(z, 0x80),
                addmod(
                    addmod(mload(z), mload(add(z, 0x20)), MODULUS),
                    mload(add(z, 0x40)),
                    MODULUS
                )
            )
        }
        return (z[3], z[4]);
    }

    function hashToG1(bytes32 _x) internal view returns (uint256, uint256) {
        uint256 x = uint256(_x) % MODULUS;
        uint256 y;
        bool found = false;
        while (true) {
            y = mulmod(x, x, MODULUS);
            y = mulmod(y, x, MODULUS);
            y = addmod(y, 3, MODULUS);
            (y, found) = sqrt(y);
            if (found) {
                return (x, y);
                break;
            }
            x = addmod(x, 1, MODULUS);
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
            mstore(
                add(freemem, 0x80),
                0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52
            )
            // N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            mstore(
                add(freemem, 0xA0),
                0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            )
            callSuccess := staticcall(
                sub(gas(), 2000),
                5,
                freemem,
                0xC0,
                freemem,
                0x20
            )
            x := mload(freemem)
            hasRoot := eq(xx, mulmod(x, x, MODULUS))
        }
        require(callSuccess, "BLS: sqrt modexp call failed");
    }
}
