// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./DataLayrServiceManagerStorage.sol";
import "../RegistrationManagerBaseMinusRepository.sol";
import "../../libraries/BytesLib.sol";
import "../../libraries/SignatureCompaction.sol";
import "../../libraries/BLS.sol";

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
     @dev This calldata is of the format:
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
    function checkSignatures(bytes calldata)
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
            BLS.addJac(aggNonSignerPubkey, pk);

            
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
            BLS.addJac(pk, aggNonSignerPubkey);

            // reorder for pairing
            (input[3], input[2], input[5], input[4]) = BLS.jacToAff(pk);
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
        (input[0], input[1]) = BLS.hashToG1(headerHash);

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
}
