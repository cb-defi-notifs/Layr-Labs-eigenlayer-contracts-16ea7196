// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./DataLayrServiceManagerStorage.sol";
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
        // uint256 totalEthStake,
        // uint256 totalEigenStake,
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
    
    // TODO: eliminate 'dumpNumber' from the calldata -- it is fetched based on the specified headerHash
    /** 
     @dev This calldata is of the format:
            <
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
        //temporary variable used to hold various numbers
        uint256 placeholder;

        assembly {
            // get the 32 bytes immediately after the function signature and length + position encoding of bytes
            // calldata type, which represents the headerHash for which disperser is calling checkSignatures
            headerHash := calldataload(68)

            // get the 6 bytes immediately after the above, which represent the
            // index of the totalStake in the 'totalStakeHistory' array
            placeholder := shr(208, calldataload(100))
        }

        // fetch the dumpNumber to confirm and block number to use for stakes from the DataLayr contract
        uint32 blockNumberFromHeaderHash;
       (dumpNumberToConfirm, , , blockNumberFromHeaderHash, ) = dataLayr.dataStores(headerHash);

        // obtain DataLayr's voteweigher contract for querying information on stake later
        IDataLayrRegistry dlRegistry = IDataLayrRegistry(
            address(repository.voteWeigher())
        );

        // to be used for holding the aggregated pub key of all DataLayr operators
        // that aren't part of the quorum
        /**
         @dev we would be storing points in G2 using Jacobian coordinates - [x0, x1, y0, y1, z0, z1]
         */
        uint256[6] memory aggNonSignerPubkey;

        // get information on total stakes
        IDataLayrRegistry.OperatorStake memory localStakeObject = dlRegistry
            .getTotalStakeFromIndex(placeholder);
        // check that the returned OperatorStake object is the most recent for the dumpNumberToConfirm
        _validateOperatorStake(localStakeObject, blockNumberFromHeaderHash);

        signedTotals.ethStakeSigned = localStakeObject.ethStake;
        signedTotals.totalEthStake = signedTotals.ethStakeSigned;
        signedTotals.eigenStakeSigned = localStakeObject.eigenStake;
        signedTotals.totalEigenStake = signedTotals.eigenStakeSigned;

        assembly {
            // get the 4 bytes immediately after the above, which represent the
            // number of DataLayr operators that aren't present in the quorum
            placeholder := shr(224, calldataload(106))
        }

        
        // we have read (68 + 32 + 6 + 4) = 114 bytes of calldata so far
        uint256 pointer = 110;

        // to be used for holding the pub key hashes of the DataLayr operators that aren't part of the quorum
        bytes32[] memory pubkeyHashes = new bytes32[](placeholder);

        /**
         @notice next step involves computing the aggregated pub key of all the DataLayr operators
                 that are not part of the quorum for this specific dumpNumber. 
         */
        /**
         @dev loading pubkey for the first DataLayr operator that is not part of the quorum as listed in the calldata; 
              Note that this need not be a special case and *could* be subsumed in the for loop below.
              However, this implementation saves one 'addJac' operation, which would be performed in the i=0 iteration otherwise. 
         */
        if (placeholder > 0) {
            uint32 stakeIndex;

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
            // We have read (32 + 32 + 32 + 32 + 4) = 132 additional bytes of calldata in the above assembly block
            // Update pointer accordingly.
            unchecked {
                pointer += 132;
            }

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
            localStakeObject = dlRegistry.getStakeFromPubkeyHashAndIndex(
                pubkeyHash,
                stakeIndex
            );
            // check that the returned OperatorStake object is the most recent for the blockNumberFromHeaderHash
            _validateOperatorStake(localStakeObject, blockNumberFromHeaderHash);
           
             
            // subtract operator stakes from totals
            signedTotals.ethStakeSigned -= localStakeObject.ethStake;
            signedTotals.eigenStakeSigned -= localStakeObject.eigenStake;
            
        }


        // temporary variable for storing the pubkey of DataLayr operators in Jacobian coordinates
        uint256[6] memory pk;
        pk[4] = 1;


        for (uint256 i = 1; i < placeholder; ) {
            //load compressed pubkey and the index in the stakes array into memory
            uint32 stakeIndex;

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

            // We have read (32 + 32 + 32 + 32 + 4) = 132 additional bytes of calldata in the above assembly block
            // Update pointer accordingly.
            unchecked {
                pointer += 132;
            }

            // get pubkeyHash and add it to pubkeyHashes of DataLayr operators that aren't part of the quorum.
            bytes32 pubkeyHash = keccak256(
                abi.encodePacked(pk[0], pk[1], pk[2], pk[3])
            );

            //pubkeys should be ordered in ascending order of hash to make proofs of signing or
            // non signing constant time
            /**
             @dev this invariant is used in forceOperatorToDisclose in DataLayrServiceManager.sol
             */
            require(
                uint256(pubkeyHash) > uint256(pubkeyHashes[i - 1]),
                "Pubkey hashes must be in ascending order"
            );

            // recording the pubkey hash
            pubkeyHashes[i] = pubkeyHash;

            // querying the VoteWeigher for getting information on the DataLayr operator's stake
            // at the time of pre-commit
            localStakeObject = dlRegistry.getStakeFromPubkeyHashAndIndex(
                pubkeyHash,
                stakeIndex
            );
            // check that the returned OperatorStake object is the most recent for the blockNumberFromHeaderHash
            _validateOperatorStake(localStakeObject, blockNumberFromHeaderHash);

            //subtract validator stakes from totals
            signedTotals.ethStakeSigned -= localStakeObject.ethStake;
            signedTotals.eigenStakeSigned -= localStakeObject.eigenStake;

            // add the pubkey of the DataLayr operator to the aggregate pubkeys in Jacobian coordinate system.
            BLS.addJac(aggNonSignerPubkey, pk);

            unchecked {
                ++i;
            }
        }

        // usage of a scoped block here minorly decreases gas usage
        {
            uint32 apkIndex;
            assembly {
                //get next 32 bits which would be the apkIndex of apkUpdates in DataLayrRegistry.sol
                apkIndex := shr(224, calldataload(pointer))

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

            // We have read (4 + 32 + 32 + 32 + 32) = 132 additional bytes of calldata in the above assembly block
            // Update pointer.
            unchecked {
                pointer += 132;
            }

            // make sure they have provided the correct aggPubKey
            require(
                dlRegistry.getCorrectApkHash(apkIndex, blockNumberFromHeaderHash) ==
                    keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3])),
                "Incorrect apk provided"
            );
        }

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

        // if at least 1 non-signer
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
            // if zero non-signers
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
            // signedTotals.totalEthStake,
            // signedTotals.totalEigenStake,
            pubkeyHashes
        );

        // set compressedSignatoryRecord variable used for payment fraud proofs
        compressedSignatoryRecord = keccak256(
            abi.encodePacked(
                // headerHash,
                dumpNumberToConfirm,
                pubkeyHashes,
                signedTotals.ethStakeSigned,
                signedTotals.eigenStakeSigned
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

    // simple internal function for validating that the OperatorStake returned from a specified index is the correct one
    function _validateOperatorStake(
        IDataLayrRegistry.OperatorStake memory opStake,
        uint32 blockNumberFromHeaderHash
    ) internal pure {
        // check that the stake returned from the specified index is recent enough
        require(
            opStake.updateBlockNumber <= blockNumberFromHeaderHash,
            "Provided stake index is too early"
        );

        /** 
          check that stake is either the most recent update for the total stake (or the operator), 
          or latest before the blockNumberFromHeaderHash
         */
        require(
            opStake.nextUpdateBlockNumber == 0 ||
                opStake.nextUpdateBlockNumber > blockNumberFromHeaderHash,
            "Provided stake index is not the most recent for dumpNumber"
        );
    }
}
