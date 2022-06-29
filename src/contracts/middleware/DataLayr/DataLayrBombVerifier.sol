// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IDataLayrRegistry.sol";
import "../../interfaces/IDataLayr.sol";
import "../../interfaces/IDataLayrEphemeralKeyRegistry.sol";
import "../../libraries/BN254_Constants.sol";
import "./DataLayrChallengeUtils.sol";

contract DataLayrBombVerifier {

    struct BombMetadata {
        uint256 dataStoreTimestamp;
        //todo: get blockhash from time of datastore
        uint256 blockhashInt;
    }

    struct HeaderHashes {
        bytes32 operatorFromHeaderHash;
        bytes32 bombHeaderHash;
        bytes32 detonationHeaderHash;
    }

    struct Indexes {
        uint32 operatorIndex;
        uint32 totalOperatorsIndex;
        uint256 detonationNonSignerIndex;
        uint256[] successiveSignerIndexes;
        uint256 bombDataStoreIndex;
    }

    struct DisclosureProof {
        bytes header;
        uint256[4] multireveal;
        bytes poly;
        uint256[4] zeroPoly;
        bytes zeroPolyProof;
        uint256[4] pi;
    }

    // bomb will trigger every once every ~2^(256-250) = 2^6 = 64 chances
    uint256 public BOMB_THRESHOLD = uint256(2)**uint256(250);

    uint256 public BOMB_FRAUDRPOOF_INTERVAL = 7 days;

    IDataLayrServiceManager public dlsm;
    IDataLayrRegistry public dlRegistry;
    IDataLayr public dataLayr;
    DataLayrChallengeUtils public challengeUtils;
    IDataLayrEphemeralKeyRegistry public dlekRegistry;

    constructor(
        IDataLayrServiceManager _dlsm,
        IDataLayrRegistry _dlRegistry,
        IDataLayr _dataLayr,
        DataLayrChallengeUtils _challengeUtils,
        IDataLayrEphemeralKeyRegistry _dlekRegistry
    ) {
        dlsm = _dlsm;
        dlRegistry = _dlRegistry;
        dataLayr = _dataLayr;
        challengeUtils = _challengeUtils;
        dlekRegistry = _dlekRegistry;
    }

    function verifyBomb(
        address operator,
        HeaderHashes calldata headerHashes,
        Indexes calldata indexes,
        IDataLayrServiceManager.SignatoryRecordMinusDumpNumber[]
            calldata signatoryRecords,
        uint256[2][2][] calldata sandwichProofs,
        DisclosureProof calldata disclosureProof
    ) external {
        {
            //require that either operator is still active, or they were previously active and they deregistered within the last 'BOMB_FRAUDRPOOF_INTERVAL'
            uint48 fromDumpNumber = dlRegistry.getOperatorFromDumpNumber(operator);
            uint256 deregisterTime = dlRegistry.getOperatorDeregisterTime(operator);
            require(fromDumpNumber != 0 && 
                (deregisterTime == 0 || deregisterTime > (block.timestamp - BOMB_FRAUDRPOOF_INTERVAL))
            );
        }
        
        (
            uint32 bombDataStoreId,
            uint32 detonationDataStoreId
        ) = verifyBombDataStoreId(
                operator,
                headerHashes.operatorFromHeaderHash,
                sandwichProofs,
                headerHashes.detonationHeaderHash,
                indexes.bombDataStoreIndex
            );
        

        /** 
          @notice Check that the DataLayr operator against whom forced disclosure is being initiated, was
                  actually part of the quorum for the @param dumpNumber.
          
                  The burden of responsibility lies with the challenger to show that the DataLayr operator 
                  is not part of the non-signers for the dump. Towards that end, challenger provides
                  @param index such that if the relationship among nonSignerPubkeyHashes (nspkh) is:
                   uint256(nspkh[0]) <uint256(nspkh[1]) < ...< uint256(nspkh[index])< uint256(nspkh[index+1]),...
                  then,
                        uint256(nspkh[index]) <  uint256(operatorPubkeyHash) < uint256(nspkh[index+1])
         */
        /**
          @dev checkSignatures in DataLayrSignaturechecker.sol enforces the invariant that hash of 
               non-signers pubkey is recorded in the compressed signatory record in an  ascending
               manner.      
        */
        {
            /** 
            Check that the information supplied as input for forced disclosure for this particular data 
            dump on DataLayr is correct
            */
            require(
                dlsm.getDumpNumberSignatureHash(detonationDataStoreId) ==
                    keccak256(
                        abi.encodePacked(
                            detonationDataStoreId,
                            signatoryRecords[0].nonSignerPubkeyHashes,
                            signatoryRecords[0].totalEthStakeSigned,
                            signatoryRecords[0].totalEigenStakeSigned
                        )
                    ),
                "Sig record does not match hash"
            );

            if (signatoryRecords[0].nonSignerPubkeyHashes.length != 0) {
                // get the pubkey hash of the DataLayr operator
                bytes32 operatorPubkeyHash = dlRegistry.getOperatorPubkeyHash(
                    operator
                );
                //not super critic: new call here, maybe change comment
                challengeUtils.checkInclusionExclusionInNonSigner(
                    operatorPubkeyHash,
                    indexes.detonationNonSignerIndex,
                    signatoryRecords[0]
                );
            }

            //verify all non signed datastores from bomb till first signed to get correct data
            for (uint i = 1; i < signatoryRecords.length; i++) {
                bytes32 operatorPubkeyHash = dlRegistry.getOperatorPubkeyHash(
                    operator
                );

                require(
                    dlsm.getDumpNumberSignatureHash(bombDataStoreId) ==
                        keccak256(
                            abi.encodePacked(
                                bombDataStoreId++,
                                signatoryRecords[i].nonSignerPubkeyHashes,
                                signatoryRecords[i].totalEthStakeSigned,
                                signatoryRecords[i].totalEigenStakeSigned
                            )
                        ),
                    "Sig record does not match hash"
                );

                require(
                    signatoryRecords[i].nonSignerPubkeyHashes[
                        indexes.successiveSignerIndexes[i - 1]
                    ] == operatorPubkeyHash,
                    "Incorrect nonsigner proof"
                );
                bombDataStoreId++;
            }
        }
        {
            (uint32 loadedBombDataStoreId, , , , ) = dataLayr.dataStores(
                keccak256(disclosureProof.header)
            );
            require(
                loadedBombDataStoreId == bombDataStoreId,
                "loaded bomb datastore id must be as calculated"
            );
        }

        require(
            nonInteractivePolynomialProof(
                headerHashes.bombHeaderHash,
                operator,
                indexes.operatorIndex,
                indexes.totalOperatorsIndex,
                disclosureProof
            ),
            "I from multireveal is not the commitment of poly"
        );

        bytes32 ek = dlekRegistry.getLatestEphemeralKey(operator);

        require(
            uint256(
                keccak256(
                    abi.encodePacked(disclosureProof.poly, ek, headerHashes.detonationHeaderHash)
                )
            ) < BOMB_THRESHOLD,
            "No bomb"
        );

        //todo: SLASH HERE
    }

    function verifyBombDataStoreId(
        address operator,
        bytes32 operatorFromHeaderHash,
        uint256[2][2][] calldata sandwichProofs,
        bytes32 detonationHeaderHash,
        uint256 bombDataStoreIndex
    ) internal returns (uint32, uint32) {
        // get init time of the dataStore corresponding to 'detonationHeaderHash'
        (,uint32 detonationTime, , ,) = dataLayr.dataStores(detonationHeaderHash);
        
        uint256 fromTime;
        {
            // get the dumpNumber at which the operator registered
            uint32 fromDataStoreId = dlRegistry.getOperatorFromDumpNumber(
                operator
            );
            // get the dumpNumber and initTime from the dataStore corresponding to 'operatorFromHeaderHash'
            (uint32 dataStoreId, uint32 fromTimeUint32, , , ) = dataLayr
                .dataStores(operatorFromHeaderHash);
            // ensure that operatorFromHeaderHash corresponds to the correct dumpNumber (i.e. the one at which the operator registered)
            require(
                fromDataStoreId == dataStoreId,
                "headerHash is not for correct operator from datastore"
            );
            // store the initTime of the dumpNumber at which the operator registered in memory
            fromTime = uint256(fromTimeUint32);
        }

        // uint32 numberActiveDataStores;
        // uint32[] memory numberActiveDataStoresForDuration;
        uint32[] memory firstDataStoreForDuration;
        // uint32 nextDataStoreIdAfterBomb;

        // (numberActiveDataStores, numberActiveDataStoresForDuration, firstDataStoreForDuration, nextDataStoreIdAfterBomb) = verifySandwiches(fromTime, bombDataStoreTimestamp, sandwichProofs);

        // uint256 bombBlockhashInt = 0;
        // uint32 selectedDataStoreIndex = uint32(bombBlockhashInt % numberActiveDataStores);
        // (uint8 durationIndex, uint32 offset) = calculateCorrectIndexAndDurationOffsetFromNumberActiveDataStoresForDuration(selectedDataStoreIndex, numberActiveDataStoresForDuration);

        (
            uint8 durationIndex,
            uint32 nextDataStoreIdAfterBomb,
            uint32 calculatedDataStoreId
        ) = verifySandwiches(
                uint256(detonationHeaderHash),
                fromTime,
                detonationTime,
                sandwichProofs
            );

        IDataLayrServiceManager.DataStoreIdPair
            memory bombDataStoreIdPair = dlsm.getDataStoreIdsForDuration(
                durationIndex + 1,
                detonationTime,
                bombDataStoreIndex
            );
        require(
            bombDataStoreIdPair.durationDataStoreId == calculatedDataStoreId,
            "datastore id provided is not the same as loaded"
        );
        {
            (uint32 detonationDataStoreId, , , ,) = dataLayr.dataStores(detonationHeaderHash);
            require(detonationDataStoreId == nextDataStoreIdAfterBomb, "next datastore after bomb does not match provided detonation datastore");
        }
        return (
            bombDataStoreIdPair.globalDataStoreId,
            nextDataStoreIdAfterBomb
        );
    }

    function verifySandwiches(
        uint256 bombBlockhashInt,
        uint256 fromTime,
        uint256 bombDataStoreTimestamp,
        uint256[2][2][] calldata sandwichProofs
    )
        internal
        returns (
            uint8,
            uint32,
            uint32
        )
    {
        //returns(uint32, uint32[] memory, uint32[] memory, uint32) {
        uint32 numberActiveDataStores;
        uint32[] memory numberActiveDataStoresForDuration = new uint32[](
            dlsm.MAX_DATASTORE_DURATION()
        );
        uint32[] memory firstDataStoreForDuration = new uint32[](
            dlsm.MAX_DATASTORE_DURATION()
        );

        uint32 nextDataStoreIdAfterBomb = type(uint32).max;

        for (uint8 i = 0; i < dlsm.MAX_DATASTORE_DURATION(); i++) {
            //if no datastores for a certain duration, go to next duration
            if (
                sandwichProofs[i][0][0] == sandwichProofs[i][0][1] &&
                sandwichProofs[i][0][0] == 0
            ) {
                require(
                    dlsm.totalDataStoresForDuration(i + 1) == 0,
                    "datastores for duration are not 0"
                );
                continue;
            }
            // calculate the greater of (init time of bombDataStoreTimestamp - (duration + 1)) and fromTime
            uint256 sandwichTimestamp = max(
                bombDataStoreTimestamp - (i + 1) * dlsm.DURATION_SCALE(),
                fromTime
            );
            //verify sandwich proofs
            firstDataStoreForDuration[i] = verifyDataStoreIdSandwich(
                sandwichTimestamp,
                i,
                sandwichProofs[i][0]
            ).durationDataStoreId;
            IDataLayrServiceManager.DataStoreIdPair
                memory endDataStoreForDurationAfterWindowIdPair = verifyDataStoreIdSandwich(
                    sandwichTimestamp,
                    i,
                    sandwichProofs[i][1]
                );
            //keep track of the next datastore id after the bomb
            if (
                nextDataStoreIdAfterBomb >
                endDataStoreForDurationAfterWindowIdPair.globalDataStoreId
            ) {
                nextDataStoreIdAfterBomb = endDataStoreForDurationAfterWindowIdPair
                    .globalDataStoreId;
            }
            //record num of datastores
            numberActiveDataStoresForDuration[i] =
                endDataStoreForDurationAfterWindowIdPair.durationDataStoreId -
                firstDataStoreForDuration[i];
            numberActiveDataStores += numberActiveDataStoresForDuration[i];
        }

        uint32 selectedDataStoreIndex = uint32(
            bombBlockhashInt % numberActiveDataStores
        );
        (
            uint8 durationIndex,
            uint32 offset
        ) = calculateCorrectIndexAndDurationOffsetFromNumberActiveDataStoresForDuration(
                selectedDataStoreIndex,
                numberActiveDataStoresForDuration
            );

        return (
            durationIndex,
            nextDataStoreIdAfterBomb,
            firstDataStoreForDuration[durationIndex] + offset
        );
        //return (numberActiveDataStores, numberActiveDataStoresForDuration, firstDataStoreForDuration, nextDataStoreIdAfterBomb);
    }

    function verifyDataStoreIdSandwich(
        uint256 sandwichTimestamp,
        uint8 duration,
        uint256[2] calldata timestamps
    ) internal view returns (IDataLayrServiceManager.DataStoreIdPair memory) {
        require(
            timestamps[0] < sandwichTimestamp,
            "timestamps[0] must be before sandwich time"
        );
        require(
            timestamps[1] >= sandwichTimestamp,
            "timestamps[1] must be at or after sandwich time"
        );

        IDataLayrServiceManager.DataStoreIdPair memory xDataStoreIdPair;
        //if not proving the first datastore
        if (timestamps[0] != 0) {
            xDataStoreIdPair = dlsm.lastDataStoreIdAtTimestampForDuration(
                duration,
                timestamps[0]
            );
        }
        IDataLayrServiceManager.DataStoreIdPair memory yDataStoreIdPair;
        //if not proving the last datastore
        if (timestamps[1] != 0) {
            yDataStoreIdPair = dlsm.firstDataStoreIdAtTimestampForDuration(
                duration,
                timestamps[1]
            );
            require(
                xDataStoreIdPair.durationDataStoreId + 1 ==
                    yDataStoreIdPair.durationDataStoreId,
                "x and y datastore must be incremental or y datastore is not first in the duration"
            );
        } else {
            //if timestamps[1] is 0, prover is claiming first datastore is the last datastore in that duration
            require(
                dlsm.totalDataStoresForDuration(duration) ==
                    xDataStoreIdPair.durationDataStoreId,
                "x datastore is not the last datastore in the duration or no datastores for duration"
            );
        }
        return yDataStoreIdPair;
    }

    function calculateCorrectIndexAndDurationOffsetFromNumberActiveDataStoresForDuration(
        uint32 offset,
        uint32[] memory numberActiveDataStoresForDuration
    ) internal pure returns (uint8, uint32) {
        uint32 offsetLeft = offset;
        uint256 i = 0;
        for (; i < numberActiveDataStoresForDuration.length; i++) {
            if (numberActiveDataStoresForDuration[i] > offsetLeft) {
                break;
            }
            offsetLeft -= numberActiveDataStoresForDuration[i];
        }

        return (uint8(i), offsetLeft);
    }

    function getChunkNumber(
        bytes32 headerHash,
        address operator,
        uint32 operatorIndex,
        uint32 totalOperatorsIndex
    ) internal view returns (uint32) {
        /**
        Get information on the dataStore for which disperser is being challenged. This dataStore was 
        constructed during call to initDataStore in DataLayr.sol by the disperser.
        */
        (
            uint32 dumpNumber,
            uint32 initTime,
            uint32 storePeriodLength,
            ,
            bool committed
        ) = dataLayr.dataStores(headerHash);

        // check that disperser had acquire quorum for this dataStore
        require(committed, "Dump is not committed yet");

        operatorIndex = dlRegistry.getOperatorIndex(
            operator,
            dumpNumber,
            operatorIndex
        );
        totalOperatorsIndex = dlRegistry.getTotalOperators(
            dumpNumber,
            totalOperatorsIndex
        );
        return (operatorIndex + dumpNumber) % totalOperatorsIndex;
    }

    function validateDisclosureResponse(
        uint256 chunkNumber,
        bytes calldata header,
        uint256[4] calldata multireveal,
        // bytes calldata poly,
        uint256[4] memory zeroPoly,
        bytes calldata zeroPolyProof
    ) public view returns (uint48) {
        (
            uint256[2] memory c,
            uint48 degree,
            uint32 numSys,
            uint32 numPar
        ) = challengeUtils
                .getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(
                    header
                );
        // modulus for the underlying field F_q of the elliptic curve
        /*
        degree is the poly length, no need to multiply 32, as it is the size of data in bytes
        require(
            (degree + 1) * 32 == poly.length,
            "Polynomial must have a 256 bit coefficient for each term"
        );
        */

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
                    challengeUtils.getLeadingCosetIndexFromHighestRootOfUnity(
                        uint32(chunkNumber),
                        numSys,
                        numPar
                    ),
                    // Merkle root hash
                    challengeUtils.getZeroPolyMerkleRoot(degree),
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

        assembly {
            // extract the proof [Pi(s).x, Pi(s).y]
            mstore(pairingInput, calldataload(36))
            mstore(add(pairingInput, 0x20), calldataload(68))

            // extract the commitment to the zero polynomial: [Z_k(s).x0, Z_k(s).x1, Z_k(s).y0, Z_k(s).y1]
            mstore(add(pairingInput, 0x40), mload(add(zeroPoly, 0x20)))
            mstore(add(pairingInput, 0x60), mload(zeroPoly))
            mstore(add(pairingInput, 0x80), mload(add(zeroPoly, 0x60)))
            mstore(add(pairingInput, 0xA0), mload(add(zeroPoly, 0x40)))

            // extract the polynomial that was committed to by the disperser while initDataStore [C.x, C.y]
            mstore(add(pairingInput, 0xC0), mload(c))
            mstore(add(pairingInput, 0xE0), mload(add(c, 0x20)))

            // extract the commitment to the interpolating polynomial [I_k(s).x, I_k(s).y] and then negate it
            // to get [I_k(s).x, -I_k(s).y]
            mstore(add(pairingInput, 0x100), calldataload(100))
            // obtain -I_k(s).y
            mstore(
                add(pairingInput, 0x120),
                addmod(0, sub(MODULUS, calldataload(132)), MODULUS)
            )
        }

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

        // check e(pi, z)e(C - I, -g2) == 1
        assembly {
            // store -g2, where g2 is the negation of the generator of group G2
            mstore(add(pairingInput, 0x100), nG2x1)
            mstore(add(pairingInput, 0x120), nG2x0)
            mstore(add(pairingInput, 0x140), nG2y1)
            mstore(add(pairingInput, 0x160), nG2y0)

            // call the precompiled ec2 pairing contract at 0x08
            if iszero(
                staticcall(
                    not(0),
                    0x08,
                    pairingInput,
                    0x180,
                    add(pairingInput, 0x180),
                    0x20
                )
            ) {
                revert(0, 0)
            }
        }

        require(pairingInput[12] == 1, "Pairing unsuccessful");
        return degree;
    }

    function nonInteractivePolynomialProof(
        bytes32 headerHash,
        address operator,
        uint32 operatorIndex,
        uint32 totalOperatorsIndex,
        DisclosureProof calldata disclosureProof
    ) internal returns (bool) {
        uint32 chunkNumber = getChunkNumber(
            headerHash,
            operator,
            operatorIndex,
            totalOperatorsIndex
        );
        (uint256[2] memory c, , , ) = challengeUtils
            .getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(
                disclosureProof.header
            );

        //verify pairing for the commitment to interpolating polynomial
        uint48 dg = validateDisclosureResponse(
            chunkNumber,
            disclosureProof.header,
            disclosureProof.multireveal,
            disclosureProof.zeroPoly,
            disclosureProof.zeroPolyProof
        );

        //Calculating r, the point at which to evaluate the interpolating polynomial
        uint256 r = uint(keccak256(disclosureProof.poly)) % MODULUS;
        uint256 s = linearPolynomialEvaluation(disclosureProof.poly, r);
        bool res = challengeUtils.openPolynomialAtPoint(
            c,
            disclosureProof.pi,
            r,
            s
        );

        if (res) {
            return true;
        }
        return false;
    }

    //evaluates the given polynomial "poly" at value "r" and returns the result
    function linearPolynomialEvaluation(bytes calldata poly, uint256 r)
        internal
        pure
        returns (uint256)
    {
        uint256 sum;
        uint length = poly.length / 32;
        uint256 rPower = 1;
        for (uint i = 0; i < length; i++) {
            uint coefficient = uint(bytes32(poly[i:i + 32]));
            sum += (coefficient * rPower);
            rPower *= r;
        }
        return sum;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return x > y ? x : y;
    }
}
