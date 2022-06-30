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
        IDataLayrServiceManager.SignatoryRecordMinusDumpNumber[] calldata signatoryRecords,
        uint256[2][2][] calldata sandwichProofs,
        DisclosureProof calldata disclosureProof
    ) external {
        {
            //require that either operator is still actively registered, or they were previously active and they deregistered within the last 'BOMB_FRAUDRPOOF_INTERVAL'
            uint48 fromDumpNumber = dlRegistry.getOperatorFromDumpNumber(operator);
            uint256 deregisterTime = dlRegistry.getOperatorDeregisterTime(operator);
            require(fromDumpNumber != 0 && 
                (deregisterTime == 0 || deregisterTime >= (block.timestamp - BOMB_FRAUDRPOOF_INTERVAL))
            );
        }

        // get globalDataStoreId at bomb DataStore, as well as detonationGlobalDataStoreId, based on input info
        (
            uint32 bombGlobalDataStoreId,
            uint32 detonationGlobalDataStoreId
        ) = verifyBombDataStoreId(
                operator,
                headerHashes.operatorFromHeaderHash,
                sandwichProofs,
                headerHashes.detonationHeaderHash,
                indexes.bombDataStoreIndex
            );
        
/*
this large block with for loop is used to iterate through DataStores
although technically the pseudo-random DataStore containing the bomb is already determined, it is possible
that the operator did not sign the 'bomb' DataStore (note that this is different than signing the 'detonator' DataStore!).
In this specific case, the 'bomb' is actually contained in the next DataStore that the operator did indeed sign.
The loop iterates through to find this next DataStore, thus determining the true 'bomb' DataStore.
*/
    // TODO: update below comment to more accurately reflect the specific usecase of this code
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
// first we verify that the operator did indeed sign the 'detonation' DataStore
        {
            // Verify that the information supplied as input related to the 'detonation' DataStore is correct 
            require(
                dlsm.getDumpNumberSignatureHash(detonationGlobalDataStoreId) ==
                    keccak256(
                        abi.encodePacked(
                            detonationGlobalDataStoreId,
                            signatoryRecords[0].nonSignerPubkeyHashes,
                            signatoryRecords[0].totalEthStakeSigned,
                            signatoryRecords[0].totalEigenStakeSigned
                        )
                    ),
                "Sig record does not match hash"
            );
            
            // fetch hash of operator's pubkey
            bytes32 operatorPubkeyHash = dlRegistry.getOperatorPubkeyHash(operator);

            // check that operator was *not* in the non-signer set (i.e. they did sign) for the 'detonation' DataStore
            if (signatoryRecords[0].nonSignerPubkeyHashes.length != 0) {
                // check that operator was *not* in the non-signer set (i.e. they did sign)
                //not super critic: new call here, maybe change comment
                challengeUtils.checkExclusionFromNonSignerSet(
                    operatorPubkeyHash,
                    indexes.detonationNonSignerIndex,
                    signatoryRecords[0]
                );
            }

//  to find the ultimate 'bomb' DataStore, we need to keep verifying that the operator *WAS* a non-signer and incrementing bombGlobalDataStoreId,
//  then verify at the end that they were *not* a non-signer (i.e. they were a signer)

            //verify all non signed DataStores from bomb till first signed to get correct data
            uint256 lengthMinusOne = signatoryRecords.length - 1;
            for (uint i = 1; i < lengthMinusOne; ++i) {            
                // Verify that the information supplied as input related to this particular DataStore is correct 
                require(
                    dlsm.getDumpNumberSignatureHash(bombGlobalDataStoreId) ==
                        keccak256(
                            abi.encodePacked(
                                bombGlobalDataStoreId++,
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
                ++bombGlobalDataStoreId;
            }

            // Verify that the information supplied as input related to the ultimate 'bomb' DataStore is correct 
            require(
                dlsm.getDumpNumberSignatureHash(bombGlobalDataStoreId) ==
                    keccak256(
                        abi.encodePacked(
                            detonationGlobalDataStoreId,
                            signatoryRecords[lengthMinusOne].nonSignerPubkeyHashes,
                            signatoryRecords[lengthMinusOne].totalEthStakeSigned,
                            signatoryRecords[lengthMinusOne].totalEigenStakeSigned
                        )
                    ),
                "Sig record does not match hash"
            );

            // check that operator was *not* in the non-signer set (i.e. they did sign) for the ultimate 'bomb' DataStore
            if (signatoryRecords[lengthMinusOne].nonSignerPubkeyHashes.length != 0) {
                // check that operator was *not* in the non-signer set (i.e. they did sign)
                //not super critic: new call here, maybe change comment
                challengeUtils.checkExclusionFromNonSignerSet(
                    operatorPubkeyHash,
                    indexes.detonationNonSignerIndex,
                    signatoryRecords[lengthMinusOne]
                );
            }
        }
        {
            // get dumpNumber from provided bomb DataStore headerHash
            (uint32 loadedBombDataStoreId, , , , ) = dataLayr.dataStores(
                keccak256(disclosureProof.header)
            );
            // verify that the correct bomb dumpNumber (the first the operator signed at or above the pseudo-random dumpNumber) matches the provided data
            require(
                loadedBombDataStoreId == bombGlobalDataStoreId,
                "loaded bomb datastore id must be as calculated"
            );
        }

        // check the disclosure of the data chunk that the operator committed to storing
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

        // fetch the operator's most recent ephemeral key
        bytes32 ek = dlekRegistry.getLatestEphemeralKey(operator);

        // check bomb requirement
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

    // return globalDataStoreId at bomb DataStore, as well as detonationGlobalDataStoreId
    function verifyBombDataStoreId(
        address operator,
        bytes32 operatorFromHeaderHash,
        uint256[2][2][] calldata sandwichProofs,
        bytes32 detonationHeaderHash,
        uint256 bombDataStoreIndex
    ) internal view returns (uint32, uint32) {
        // get init time of the dataStore corresponding to 'detonationHeaderHash'
        (,uint32 detonationDataStoreInitTimestamp, , ,) = dataLayr.dataStores(detonationHeaderHash);
        
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
        // find the specific DataStore containing the bomb, specified by durationIndex and calculatedDataStoreId
        // 'verifySandwiches' gets a pseudo-randomized durationIndex and durationDataStoreId, as well as the nextGlobalDataStoreIdAfterBomb
        (
            uint8 durationIndex,
            uint32 calculatedDataStoreId,
            uint32 nextGlobalDataStoreIdAfterBomb
        ) = verifySandwiches(
                uint256(detonationHeaderHash),
                fromTime,
                detonationDataStoreInitTimestamp,
                sandwichProofs
            );

        // fetch the durationDataStoreId and globalDataStoreId for the specific 'detonation' DataStore specified by the parameters
        IDataLayrServiceManager.DataStoreIdPair
            memory bombDataStoreIdPair = dlsm.getDataStoreIdsForDuration(
                durationIndex + 1,
                detonationDataStoreInitTimestamp,
                bombDataStoreIndex
            );
        // check that the specified bombDataStore info matches the calculated info 
        require(
            bombDataStoreIdPair.durationDataStoreId == calculatedDataStoreId,
            "datastore id provided is not the same as loaded"
        );
        {
            // get the dumpNumber for 'detonationHeaderHash'
            (uint32 detonationGlobalDataStoreId, , , ,) = dataLayr.dataStores(detonationHeaderHash);
            // check that the dumpNumber for the provided detonationHeaderHash matches the calculated value
            require(detonationGlobalDataStoreId == nextGlobalDataStoreIdAfterBomb, "next datastore after bomb does not match provided detonation datastore");
        }
        // return globalDataStoreId at bomb DataStore, as well as detonationGlobalDataStoreId
        return (
            bombDataStoreIdPair.globalDataStoreId,
            // note that this matches detonationGlobalDataStoreId, as checked above
            nextGlobalDataStoreIdAfterBomb
        );
    }

    // returns a pseudo-randomized durationIndex and durationDataStoreId, as well as the nextGlobalDataStoreIdAfterBomb
    function verifySandwiches(
        uint256 detonationHeaderHashValue,
        uint256 fromTime,
        uint256 detonationDataStoreInitTimestamp,
        uint256[2][2][] calldata sandwichProofs
    )
        internal view
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

        uint32 nextGlobalDataStoreIdAfterBomb = type(uint32).max;

        for (uint8 i = 0; i < dlsm.MAX_DATASTORE_DURATION(); ++i) {
            // i is loop index, (i + 1) is duration

            //if no DataStores for a certain duration, go to next duration
            if (
                sandwichProofs[i][0][0] == sandwichProofs[i][0][1] &&
                sandwichProofs[i][0][0] == 0
            ) {
                require(
                    dlsm.totalDataStoresForDuration(i + 1) == 0,
                    "DataStores for duration are not 0"
                );
                continue;
            }
            /*
                calculate the greater of ((init time of detonationDataStoreInitTimestamp) - duration) and fromTime
                since 'fromTime' is the time at which the operator registered, if
                fromTime is > (init time of detonationDataStoreInitTimestamp) - duration), then we only care about DataStores
                starting from 'fromTime'
            */
            uint256 sandwichTimestamp = max(
                detonationDataStoreInitTimestamp - (i + 1) * dlsm.DURATION_SCALE(),
                fromTime
            );
            //verify sandwich proofs
            // fetch the first durationDataStoreId at or after the sandwichTimestamp, for duration (i.e. i+1)
            firstDataStoreForDuration[i] = verifyDataStoreIdSandwich(
                sandwichTimestamp,
                i + 1,
                sandwichProofs[i][0]
            ).durationDataStoreId;
            // fetch the first durationDataStoreId and globalDataStoreId at or after the detonationDataStoreInitTimestamp, for duration (i.e. i+1)
            IDataLayrServiceManager.DataStoreIdPair memory detonationDataStoreIdPair = 
                verifyDataStoreIdSandwich(
                    detonationDataStoreInitTimestamp,
                    i + 1,
                    sandwichProofs[i][1]
            );
            // keep track of the next globalDataStoreId after the bomb
            // check this for all the durations, and reduce the value in memory whenever a value for a specific duration is lower than current value
            if (nextGlobalDataStoreIdAfterBomb > detonationDataStoreIdPair.globalDataStoreId) {
                nextGlobalDataStoreIdAfterBomb = detonationDataStoreIdPair.globalDataStoreId;
            }
            //record number of DataStores for duration
            numberActiveDataStoresForDuration[i] =
                detonationDataStoreIdPair.durationDataStoreId -
                firstDataStoreForDuration[i];
            // add number of DataStores (for this specific duration) to sum
            numberActiveDataStores += numberActiveDataStoresForDuration[i];
        }

        // find the pseudo-randomly determined DataStore containing the bomb
        uint32 selectedDataStoreIndex = uint32(
            detonationHeaderHashValue % numberActiveDataStores
        );
        // find the durationIndex and offset within the set of DataStores for that specific duration from the 'selectedDataStoreIndex'
        // we can think of this as the DataStore location specified by 'selectedDataStoreIndex'
        (
            uint8 durationIndex,
            uint32 offset
        ) = calculateCorrectIndexAndDurationOffsetFromNumberActiveDataStoresForDuration(
                selectedDataStoreIndex,
                numberActiveDataStoresForDuration
            );

        // return the pseudo-randomized durationIndex and durationDataStoreId, specified by selectedDataStoreIndex, as well as the nextGlobalDataStoreIdAfterBomb
        return (
            durationIndex,
            firstDataStoreForDuration[durationIndex] + offset,
            nextGlobalDataStoreIdAfterBomb
        );
    }

    // checks that the provided timestamps accurately specify the first dataStore, with the specified duration, which was created at or after 'sandwichTimestamp'
    // returns the first durationDataStoreId and globalDataStoreId at or after the sandwichTimestamp, for the specified duration
    function verifyDataStoreIdSandwich(
        uint256 sandwichTimestamp,
        uint8 duration,
        uint256[2] calldata timestamps
    ) internal view returns (IDataLayrServiceManager.DataStoreIdPair memory) {
        // make sure that the first timestamp is strictly before the sandwichTimestamp
        require(
            timestamps[0] < sandwichTimestamp,
            "timestamps[0] must be before sandwich time"
        );
        // make sure that the second timestamp is at or after the sandwichTimestamp
        require(
            timestamps[1] >= sandwichTimestamp,
            "timestamps[1] must be at or after sandwich time"
        );

        IDataLayrServiceManager.DataStoreIdPair memory xDataStoreIdPair;
        //if not proving the first datastore
        if (timestamps[0] != 0) {
            // fetch the *last* durationDataStoreId and globalDataStoreId, created at the exact UTC timestamp specified by 'timestamp[0]' 
            xDataStoreIdPair = dlsm.lastDataStoreIdAtTimestampForDuration(
                duration,
                timestamps[0]
            );
        }
        IDataLayrServiceManager.DataStoreIdPair memory yDataStoreIdPair;
        //if not proving the most recent datastore
        if (timestamps[1] != 0) {
            // fetch the *first* durationDataStoreId and globalDataStoreId, created at the exact UTC timestamp specified by 'timestamp[1]' 
            yDataStoreIdPair = dlsm.firstDataStoreIdAtTimestampForDuration(
                duration,
                timestamps[1]
            );
            // for the durationDataStoreId's that we just looked up, make sure that the first durationDataStoreId is just before the second durationDataStoreId
            require(
                xDataStoreIdPair.durationDataStoreId + 1 ==
                    yDataStoreIdPair.durationDataStoreId,
                "x and y datastore must be incremental"
            );
        } else {
            //if timestamps[1] is 0, prover is claiming first datastore is the most recent datastore for that duration
            require(
                dlsm.totalDataStoresForDuration(duration) ==
                    xDataStoreIdPair.durationDataStoreId,
                "x datastore is not the most recent datastore for the duration"
            );
        }
        // return the first durationDataStoreId and globalDataStoreId at or after the sandwichTimestamp, for the specified duration
        return yDataStoreIdPair;
    }

    // inputs are a pseudo-random 'offset' value and an array of the number of active DataStores, ordered by duration
    // given the 'offset' value, this function moves through the 'duration' bins, and returns the bin and offset *within that bin* corresponding to 'offset'
    // in other words, it finds the position for the 'offset'-th entry, specified by a duration 'bin' and a value corresponding to a specific DataStore within that bin
    function calculateCorrectIndexAndDurationOffsetFromNumberActiveDataStoresForDuration(
        uint32 offset,
        uint32[] memory numberActiveDataStoresForDuration
    ) internal pure returns (uint8, uint32) {
        uint32 offsetLeft = offset;
        uint256 i = 0;
        for (; i < numberActiveDataStoresForDuration.length; ++i) {
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
            ,
            ,
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


    function nonInteractivePolynomialProof(
        bytes32 headerHash,
        address operator,
        uint32 operatorIndex,
        uint32 totalOperatorsIndex,
        DisclosureProof calldata disclosureProof
    ) internal view returns (bool) {
        uint32 chunkNumber = getChunkNumber(
            headerHash,
            operator,
            operatorIndex,
            totalOperatorsIndex
        );
        bool res = challengeUtils.nonInteractivePolynomialProof(
            chunkNumber,
            disclosureProof.header,
            disclosureProof.multireveal,
            disclosureProof.poly,
            disclosureProof.zeroPoly,
            disclosureProof.zeroPolyProof,
            disclosureProof.pi
        );

        return res;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return x > y ? x : y;
    }
}
