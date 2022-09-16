// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IQuorumRegistry.sol";
import "../../interfaces/IEphemeralKeyRegistry.sol";
import "../../libraries/DataStoreUtils.sol";
import "./DataLayrChallengeUtils.sol";
import "../../libraries/DataStoreUtils.sol";
import "../../libraries/BN254.sol";

contract DataLayrBombVerifier {
    struct DataStoresForDuration {
        uint256 timestamp;
        uint32 index;
        IDataLayrServiceManager.DataStoreMetadata metadata;
    }

    struct DataStoreProofs {
        IDataLayrServiceManager.DataStoreSearchData operatorFromDataStore;
        IDataLayrServiceManager.DataStoreSearchData[] bombDataStores;
        IDataLayrServiceManager.DataStoreSearchData detonationDataStore;
    }

    struct Indexes {
        uint32 operatorIndex;
        uint32 totalOperatorsIndex;
        uint256 detonationNonSignerIndex;
        uint256[] successiveSignerIndexes;
    }

    struct DisclosureProof {
        bytes header;
        bytes poly;
        DataLayrChallengeUtils.MultiRevealProof multiRevealProof;
        BN254.G2Point polyEquivalenceProof;
    }

    // bomb will trigger every once every ~2^(256-249) = 2^7 = 128 chances
    // BOMB_THRESHOLD can be tuned up to increase the chance of bombs and therefore
    // reduce the expected value of not storing the data
    // BOMB_THRESHOLD can be tuned down to decrease the chance of bombs and therefore
    // increase the amount of nodes that will sign off on datastores
    uint256 public BOMB_THRESHOLD = uint256(2) ** uint256(249);

    uint256 public BOMB_FRAUDRPOOF_INTERVAL = 7 days;

    IDataLayrServiceManager public immutable dlsm;
    IQuorumRegistry public immutable dlRegistry;
    DataLayrChallengeUtils public immutable challengeUtils;
    IEphemeralKeyRegistry public immutable dlekRegistry;

    constructor(
        IDataLayrServiceManager _dlsm,
        IQuorumRegistry _dlRegistry,
        DataLayrChallengeUtils _challengeUtils,
        IEphemeralKeyRegistry _dlekRegistry
    ) {
        dlsm = _dlsm;
        dlRegistry = _dlRegistry;
        challengeUtils = _challengeUtils;
        dlekRegistry = _dlekRegistry;
    }

    // The DETONATION datastore is the datastore whose header hash is mapped to one of the active datastores at its time of initialization
    // The datastore that the DETONATION datastore is mapped to is called the BOMB datastore
    // The BOMB datastore is the datastore whose data, when hashed with some auxillary information was below BOMB_THRESHOLD (the BOMB condition)
    // If such was the case, the operator should not have signed the DETONATION datastore

    // In datalayr, every datastore is a potential DETONATION datastore, and it's corresponding potential BOMB datastore should
    // always be checked for the BOMB condition
    // The sender of this function is a party that is proving the existence of a certain operator that signed a DETONATION datastore whose corresponding
    // BOMB datastore met the BOMB condition

    //tick, tick, tick, tick, ⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️

    // signatoryRecords input is formatted as following, with 'n' being its length:
    // signatoryRecords[0] is for the 'detonation' DataStore
    // signatoryRecords[1] through (inclusive) signatoryRecords[n-2] is for the DataStores starting at the 'bomb'
    // DataStore returned by the 'verifyBombDataStoreId' function and any immediately following series DataStores *that the operator did NOT sign*
    // signatoryRecords[n] is for the DataStore that is ultimately treated as the 'bomb' DataStore
    // this will be the first DataStore at or after the DataStore returned by the 'verifyBombDataStoreId' function *that the operator DID sign*
    function verifyBomb(
        address operator,
        DataStoreProofs calldata dataStoreProofs,
        Indexes calldata indexes,
        IDataLayrServiceManager.SignatoryRecordMinusDataStoreId[] calldata signatoryRecords,
        DataStoresForDuration[2][2][] calldata sandwichProofs,
        DisclosureProof calldata disclosureProof
    )
        external
    {
        require(
            verifyMetadataPreImage(dataStoreProofs.operatorFromDataStore),
            "DataLayrBombVerifier.verifyBomb: operatorFrom metadata preimage incorrect"
        );
        require(
            verifyMetadataPreImage(dataStoreProofs.detonationDataStore),
            "DataLayrBombVerifier.verifyBomb: detonation metadata preimage incorrect"
        );

        {
            //require that either operator is still actively registered, or they were previously active and they deregistered within the last 'BOMB_FRAUDRPOOF_INTERVAL'
            //get the id of the datastore the operator has been serving since
            uint32 fromDataStoreId = dlRegistry.getFromTaskNumberForOperator(operator);
            //deregisterTime is 0 if the operator is still registered and serving
            //otherwise it is the time at will/have stopped serving all of their existing datstores
            uint256 deregisterTime = dlRegistry.getOperatorDeregisterTime(operator);
            //Require that the operator is registrered and, if they have deregistered, it is still before the bomb fraudproof interval has passed
            require(
                fromDataStoreId != 0
                    && (deregisterTime == 0 || deregisterTime >= (block.timestamp - BOMB_FRAUDRPOOF_INTERVAL)),
                "DataLayrBombVerifier.verifyBomb: invalid operator or time"
            );
        }

        // get globalDataStoreId at bomb DataStore, as well as detonationGlobalDataStoreId, based on input info
        uint32 bombGlobalDataStoreId = verifyBombDataStoreId(operator, dataStoreProofs, sandwichProofs);

        /*
            this large block with for loop is used to iterate through DataStores
            although technically the pseudo-random DataStore containing the bomb is already determined, it is possible
            that the operator did not sign the 'bomb' DataStore (note that this is different than signing the 'detonator' DataStore!).
            In this specific case, the 'bomb' is actually contained in the next DataStore that the operator did indeed sign.
            The loop iterates through to find this next DataStore, thus determining the true 'bomb' DataStore.
        */
        /**
         * @notice Check that the DataLayr operator against whom bomb is being verified, was
         * actually part of the quorum for the detonation dataStoreId.
         *
         * The burden of responsibility lies with the challenger to show that the DataLayr operator
         * is not part of the non-signers for the dump. Towards that end, challenger provides
         * an index such that if the relationship among nonSignerPubkeyHashes (nspkh) is:
         * uint256(nspkh[0]) <uint256(nspkh[1]) < ...< uint256(nspkh[index])< uint256(nspkh[index+1]),...
         * then,
         * uint256(nspkh[index]) <  uint256(operatorPubkeyHash) < uint256(nspkh[index+1])
         */
        /**
         * @dev checkSignatures in DataLayrBLSSignatureChecker.sol enforces the invariant that hash of
         * non-signers pubkey is recorded in the compressed signatory record in an  ascending
         * manner.
         */
        // first we verify that the operator did indeed sign the 'detonation' DataStore
        {
            //the block number since the operator has been active
            uint32 operatorActiveFromBlockNumber = dlRegistry.getFromBlockNumberForOperator(operator);
            // fetch hash of operator's pubkey
            bytes32 operatorPubkeyHash = dlRegistry.getOperatorPubkeyHash(operator);

            // The BOMB datastore must be a datastore for which a signature from the operator has been submitted on chain
            // Then, we have an attestation that they have stored said data, so they can check it for the BOMB condition
            uint256 ultimateBombDataStoreIndex = dataStoreProofs.bombDataStores.length - 1;
            //verify all non signed DataStores from bomb till first signed to get correct BOMB datastore
            for (uint256 i = 0; i < ultimateBombDataStoreIndex; ++i) {
                require(
                    dataStoreProofs.bombDataStores[i].metadata.globalDataStoreId == bombGlobalDataStoreId,
                    "DataLayrBombVerifier.verifyBomb: bombDataStore is not for correct id"
                );
                //verify the preimage of the i'th bombDataStore is consistent with storage
                require(
                    verifyMetadataPreImage(dataStoreProofs.bombDataStores[i]),
                    "DataLayrBombVerifier.verifyBomb: bombDataStores metadata preimage incorrect"
                );

                //There are 2 conditions under which the BOMB datastore id must increment
                //1. The BOMB datastore is based off of stakes before the operator joined
                //2. The BOMB datastore included the stake of the operator, but the operator did not sign
                //This conditional statement checks (1)
                if (dataStoreProofs.bombDataStores[i].metadata.blockNumber < operatorActiveFromBlockNumber) {
                    //If we make it inside of this loop, then the BOMB datastore included the operator's stake
                    //So we check the proof that the operator did not sign for this datastore
                    // Verify that the signatoryRecord supplied as input related to the i'th potential BOMB datastore is correct
                    require(
                        //will be bytes32(0) if this datastore was never confirmed
                        dataStoreProofs.bombDataStores[i].metadata.signatoryRecordHash == bytes32(0)
                            || dataStoreProofs.bombDataStores[i].metadata.signatoryRecordHash
                                == keccak256(
                                    abi.encodePacked(
                                        bombGlobalDataStoreId,
                                        signatoryRecords[i].nonSignerPubkeyHashes,
                                        signatoryRecords[i].totalEthStakeSigned,
                                        signatoryRecords[i].totalEigenStakeSigned
                                    )
                                ),
                        "DataLayrBombVerifier.verifyBomb: Bomb datastore signatory record does not match hash"
                    );

                    require(
                        signatoryRecords[i].nonSignerPubkeyHashes[indexes.successiveSignerIndexes[i]]
                            == operatorPubkeyHash,
                        "DataLayrBombVerifier.verifyBomb: Incorrect Bomb datastore nonsigner proof"
                    );
                }
                ++bombGlobalDataStoreId;
            }

            require(
                dataStoreProofs.bombDataStores[ultimateBombDataStoreIndex].metadata.globalDataStoreId
                    == bombGlobalDataStoreId,
                "DataLayrBombVerifier.verifyBomb: bombDataStore is not for correct id"
            );

            //verify the preimage of the last provided BOMB datastore (the valid one) is consistent with storage
            require(
                verifyMetadataPreImage(dataStoreProofs.bombDataStores[ultimateBombDataStoreIndex]),
                "DataLayrBombVerifier.verifyBomb: BOMB datastore metadata preimage incorrect"
            );

            //Verify that the signatory record supplied as input related to the ultimate 'bomb' DataStore is correct
            require(
                dataStoreProofs.bombDataStores[ultimateBombDataStoreIndex].metadata.signatoryRecordHash
                    == keccak256(
                        abi.encodePacked(
                            dataStoreProofs.bombDataStores[ultimateBombDataStoreIndex].metadata.globalDataStoreId,
                            signatoryRecords[ultimateBombDataStoreIndex].nonSignerPubkeyHashes,
                            signatoryRecords[ultimateBombDataStoreIndex].totalEthStakeSigned,
                            signatoryRecords[ultimateBombDataStoreIndex].totalEigenStakeSigned
                        )
                    ),
                "DataLayrBombVerifier.verifyBomb: BOMB datastore sig record does not match hash"
            );

            //require that the detonation is happening for a datastore using the operators stake
            require(
                dataStoreProofs.bombDataStores[ultimateBombDataStoreIndex].metadata.blockNumber
                    >= operatorActiveFromBlockNumber,
                "DataLayrBombVerifier.verfiyBomb: BOMB datastore was not using the operator's stake"
            );

            // check that operator was *not* in the non-signer set (i.e. they did sign) for the ultimate 'bomb' DataStore
            if (signatoryRecords[ultimateBombDataStoreIndex].nonSignerPubkeyHashes.length != 0) {
                // check that operator was *not* in the non-signer set (i.e. they did sign)
                //not super critic: new call here, maybe change comment
                challengeUtils.checkExclusionFromNonSignerSet(
                    operatorPubkeyHash, indexes.detonationNonSignerIndex, signatoryRecords[ultimateBombDataStoreIndex]
                );
            }

            //Verify that the operator did sign the DETONATION datastore
            uint256 lastSignatoryRecordIndex = signatoryRecords.length - 1;

            // Verify that the signatoryRecord supplied as input related to the 'detonation' DataStore is correct
            //NOTE that signatoryRecords[signatoryRecords.length - 1] is the signatory record for the DETONATION datastore
            require(
                dataStoreProofs.detonationDataStore.metadata.signatoryRecordHash
                    == keccak256(
                        abi.encodePacked(
                            dataStoreProofs.detonationDataStore.metadata.globalDataStoreId,
                            signatoryRecords[lastSignatoryRecordIndex].nonSignerPubkeyHashes,
                            signatoryRecords[lastSignatoryRecordIndex].totalEthStakeSigned,
                            signatoryRecords[lastSignatoryRecordIndex].totalEigenStakeSigned
                        )
                    ),
                "DataLayrBombVerifier.verifyBomb: Detonation singatory record does not match hash"
            );
            //require that the detonation is happening for a datastore using the operators stake
            require(
                dataStoreProofs.detonationDataStore.metadata.blockNumber > operatorActiveFromBlockNumber,
                "DataLayrBombVerifier.verfiyBomb: Detonation datastore was not using the operator's stake"
            );

            // check that operator was *not* in the non-signer set (i.e. they did sign) for the 'detonation' DataStore
            if (signatoryRecords[lastSignatoryRecordIndex].nonSignerPubkeyHashes.length != 0) {
                // check that operator was *not* in the non-signer set (i.e. they did sign)
                //not super critic: new call here, maybe change comment
                challengeUtils.checkExclusionFromNonSignerSet(
                    operatorPubkeyHash, indexes.detonationNonSignerIndex, signatoryRecords[lastSignatoryRecordIndex]
                );
            }
        }

        // verify that the correct BOMB dataStoreId (the first the operator signed at or above the pseudo-random dataStoreId) matches the provided data
        require(
            dataStoreProofs.bombDataStores[dataStoreProofs.bombDataStores.length - 1].metadata.globalDataStoreId
                == bombGlobalDataStoreId,
            "DataLayrBombVerifier.verifyBomb: provided bomb datastore id must be as calculated"
        );

        // check the disclosure of the data chunk that the operator committed to storing
        require(
            nonInteractivePolynomialProof(
                // headerHashes.bombHeaderHash,
                operator,
                indexes.operatorIndex,
                indexes.totalOperatorsIndex,
                bombGlobalDataStoreId,
                disclosureProof,
                dataStoreProofs.operatorFromDataStore
            ),
            "DataLayrBombVerifier.verifyBomb: I from multireveal is not the commitment of poly"
        );

        // fetch the operator's most recent ephemeral key
        bytes32 ek = dlekRegistry.getEphemeralKeyForTaskNumber(
            operator, dataStoreProofs.detonationDataStore.metadata.globalDataStoreId
        );

        // The bomb "condition" is that keccak(data, ek, headerHash) < BOMB_THRESHOLD
        // If it is was met, there was a .....  ⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️⏲️
        // 💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣
        // 💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣💣
        // 💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥
        // 💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥
        require(
            uint256(
                keccak256(
                    abi.encodePacked(disclosureProof.poly, ek, dataStoreProofs.detonationDataStore.metadata.headerHash)
                )
            ) < BOMB_THRESHOLD,
            "DataLayrBombVerifier.verifyBomb: No bomb"
        );

        dlsm.freezeOperator(operator);
    }

    // return globalDataStoreId at bomb DataStore
    function verifyBombDataStoreId(
        address operator,
        DataStoreProofs calldata dataStoreProofs,
        DataStoresForDuration[2][2][] calldata sandwichProofs
    )
        internal
        view
        returns (uint32)
    {
        uint256 fromTime;
        {
            // get the dataStoreId at which the operator registered
            uint32 fromDataStoreId = dlRegistry.getFromTaskNumberForOperator(operator);

            // ensure that operatorFromHeaderHash corresponds to the correct dataStoreId (i.e. the one at which the operator registered)
            require(
                fromDataStoreId == dataStoreProofs.operatorFromDataStore.metadata.globalDataStoreId,
                "DataLayrBombVerifier.verifyBombDataStoreId: headerHash is not for correct operator from datastore"
            );
            // store the initTime of the dataStoreId at which the operator registered in memory
            fromTime = dataStoreProofs.operatorFromDataStore.timestamp;
        }

        // find the specific DataStore containing the bomb, specified by durationIndex and calculatedDataStoreId
        // 'verifySandwiches' gets a pseudo-randomized durationIndex and durationDataStoreId, as well as the nextGlobalDataStoreIdAfterBomb
        (uint8 duration, uint32 calculatedDataStoreId, uint32 nextGlobalDataStoreIdAfterDetonationTimestamp) =
        verifySandwiches(
            uint256(dataStoreProofs.detonationDataStore.metadata.headerHash),
            fromTime,
            dataStoreProofs.detonationDataStore.timestamp,
            sandwichProofs
        );

        require(
            sandwichProofs.length == dlsm.MAX_DATASTORE_DURATION() + 1,
            "DataLayrBombVerifier.verifyBombDataStoreId: Incorrect sandwich proof length. *must account for last proof of bomb datastoremetdata"
        );

        // fetch the durationDataStoreId and globalDataStoreId for the specific 'detonation' DataStore specified by the parameters
        // check that the specified bombDataStore info matches the calculated info
        require(
            dataStoreProofs.bombDataStores[0].duration == duration,
            "DataLayrBombVerifier.verifyBombDataStoreId: bomb datastore id's duration is the same as calculated"
        );
        require(
            dataStoreProofs.bombDataStores[0].metadata.durationDataStoreId == calculatedDataStoreId,
            "DataLayrBombVerifier.verifyBombDataStoreId: bomb datastore id provided is not the same as calculated"
        );

        // get the dataStoreId for 'detonationHeaderHash'
        // check that the dataStoreId for the provided detonationHeaderHash matches the calculated value
        require(
            dataStoreProofs.detonationDataStore.metadata.globalDataStoreId
                == nextGlobalDataStoreIdAfterDetonationTimestamp,
            "DataLayrBombVerifier.verifyBombDataStoreId: next datastore after bomb does not match provided detonation datastore"
        );
        // return globalDataStoreId at bomb DataStore, as well as detonationGlobalDataStoreId
        return dataStoreProofs.bombDataStores[0].metadata.globalDataStoreId;
        // note that this matches detonationGlobalDataStoreId, as checked above;
    }

    // returns a pseudo-randomized durationIndex and durationDataStoreId, as well as the nextGlobalDataStoreIdAfterBomb
    /**
     * Finds all of the active datastores after @param fromTime and before @param detonationDataStoreInitTimestamp.
     *
     * @param sandwichProofs is a list of the length of the number of durations that datastores cna be stored. Each element is
     * 2 sandwich proofs of the datastores surrounding the boundaries of the duration. For example, if the first duration is 1 day,
     * then sandwichProofs[0][0] is a proof of the 2 datastores for duration 1 day surrounding @param detonationDataStoreInitTimestamp - 1 day or
     * @param fromTime. sandwichProofs[0][1] is a proof of the 2 datastores for duration 1 day surrounding @param detonationDataStoreInitTimestamp
     *
     * Then the BOMB datastore is picked from random by taking @param detonationHeaderHashValue. TODO: Finish this comment
     */
    function verifySandwiches(
        uint256 detonationHeaderHashValue,
        uint256 fromTime,
        uint256 detonationDataStoreInitTimestamp,
        DataStoresForDuration[2][2][] calldata sandwichProofs
    )
        internal
        view
        returns (uint8, uint32, uint32)
    {
        uint32 numberActiveDataStores;
        //This is a list of the number of active datastores for each duration
        //at the time of initialization of the DETONATION datastore
        uint32[] memory numberActiveDataStoresForDuration = new uint32[](
            dlsm.MAX_DATASTORE_DURATION()
        );
        //This is a list of the ids of the earliest active datastore for
        //each duration at the time of initialization of the DETONATION datastore
        uint32[] memory firstDataStoreForDuration = new uint32[](
            dlsm.MAX_DATASTORE_DURATION()
        );

        uint32 nextGlobalDataStoreIdAfterDetonationTimestamp = type(uint32).max;

        //for each duration
        for (uint8 i = 0; i < dlsm.MAX_DATASTORE_DURATION(); ++i) {
            // NOTE THAT i is loop index and (i + 1) is duration
            //If there are no datastores for certain duration, the prover should set the timestamps for the first sandwich proofs for that duration
            //equal to zero
            if (
                sandwichProofs[i][0][0].timestamp == sandwichProofs[i][0][1].timestamp
                    && sandwichProofs[i][0][0].timestamp == 0
            ) {
                //prover is claiming no datastores for given duration
                require(
                    dlsm.totalDataStoresForDuration(i + 1) == 0,
                    "DataLayrBombVerifier.verifySandwiches: DataStores for duration are not 0"
                );
                //if storage agrees with provers claims, continue to next duration
                continue;
            }
            /*
                calculate the greater of ((init time of detonationDataStoreInitTimestamp) - duration) and fromTime
                since 'fromTime' is the time at which the operator registered, if
                fromTime is > (init time of detonationDataStoreInitTimestamp) - duration), then we only care about DataStores
                starting from 'fromTime'
            */
            uint256 sandwichTimestamp =
                max(detonationDataStoreInitTimestamp - (i + 1) * dlsm.DURATION_SCALE(), fromTime);
            //verify the sandwich proof for the given duration. `verifyDataStoreIdSandwich` will return the the second datastore in the sandwich's metadata
            //the second datastore is the first datastore after sandwichTimestamp. this is the first active datastore for the duration at the detonationDataStoreInitTimestamp
            //in memory, store it's durationDataStoreId
            firstDataStoreForDuration[i] =
                verifyDataStoreIdSandwich(sandwichTimestamp, i + 1, sandwichProofs[i][0]).durationDataStoreId;
            // verify the sandwich proof and store the metadata of the first datastore after detonationDataStoreInitTimestamp for the given duration
            IDataLayrServiceManager.DataStoreMetadata memory detonationDataStoreMetadata =
                verifyDataStoreIdSandwich(detonationDataStoreInitTimestamp, i + 1, sandwichProofs[i][1]);
            //The DETONATION datastore id is the nextGlobalDataStoreIdAfterDetonationTimestamp: the datastore with the lowest datastoreid after
            //the detonationDataStoreMetadata
            //TODO: is this sound? think so
            if (nextGlobalDataStoreIdAfterDetonationTimestamp > detonationDataStoreMetadata.globalDataStoreId) {
                nextGlobalDataStoreIdAfterDetonationTimestamp = detonationDataStoreMetadata.globalDataStoreId;
            }
            //record number of DataStores for duration
            numberActiveDataStoresForDuration[i] =
                detonationDataStoreMetadata.durationDataStoreId - firstDataStoreForDuration[i];
            // add number of DataStores (for this specific duration) to sum
            numberActiveDataStores += numberActiveDataStoresForDuration[i];
        }

        // find the pseudo-randomly determined DataStore containing the bomb
        // just by taking detonationHeaderHashValue modulo the number of active datastores at the time
        uint32 selectedDataStoreIndex = uint32(detonationHeaderHashValue % numberActiveDataStores);
        // find the durationIndex and offset within the set of DataStores for that specific duration from the 'selectedDataStoreIndex'
        // we can think of this as the DataStore location specified by 'selectedDataStoreIndex'
        (uint8 durationIndex, uint32 offset) =
        calculateCorrectIndexAndDurationOffsetFromNumberActiveDataStoresForDuration(
            selectedDataStoreIndex, numberActiveDataStoresForDuration
        );

        // return the pseudo-randomized durationIndex and durationDataStoreId, specified by selectedDataStoreIndex, as well as the nextGlobalDataStoreIdAfterBomb
        return (
            durationIndex + 1,
            firstDataStoreForDuration[durationIndex] + offset,
            nextGlobalDataStoreIdAfterDetonationTimestamp
        );
    }

    // checks that the provided timestamps accurately specify the first dataStore, with the specified duration, which was created at or after 'sandwichTimestamp'
    // returns the first durationDataStoreId and globalDataStoreId at or after the sandwichTimestamp, for the specified duration

    /**
     * For a certain @param duration, checks that the two datastores provided in @param sandwich
     * are the datastores just before and after (or equal) @param sandwichTimestamp in that order
     */
    function verifyDataStoreIdSandwich(
        uint256 sandwichTimestamp,
        uint8 duration,
        DataStoresForDuration[2] calldata sandwich
    )
        internal
        view
        returns (IDataLayrServiceManager.DataStoreMetadata memory)
    {
        // make sure that the first timestamp is strictly before the sandwichTimestamp
        require(
            sandwich[0].timestamp < sandwichTimestamp,
            "DataLayrBombVerifier.verifyDataStoreIdSandwich: sandwich[0].timestamp must be before sandwich time"
        );
        // make sure that the second timestamp is at or after the sandwichTimestamp
        require(
            sandwich[1].timestamp >= sandwichTimestamp,
            "DataLayrBombVerifier.verifyDataStoreIdSandwich: sandwich[1].timestamp must be at or after sandwich time"
        );

        // If sandwichTimestamp is before the first datastore for the given duration, set sandwich[0].timestamp equal to 0
        // because there is no datastore before sandwichTimestamp for the duration
        if (sandwich[0].timestamp != 0) {
            // There is a datastore before sandwichTimestamp for the duration
            // Verify that the provided metadata of the datastore before sandwichTimestamp (sandwich[0])
            // agrees with the stored hash
            require(
                dlsm.getDataStoreHashesForDurationAtTimestamp(duration, sandwich[0].timestamp, sandwich[0].index)
                    == DataStoreUtils.computeDataStoreHash(sandwich[0].metadata),
                "DataLayrBombVerifier.verifyDataStoreIdSandwich: sandwich[0].metadata preimage is incorrect"
            );
        }
        // If sandwichTimestamp is after the last datastore for the given duration, set sandwich[1].timestamp equal to 0
        // because there is no datastore after sandwichTimestamp for the duration
        if (sandwich[1].timestamp != 0) {
            // There is a datastore before sandwichTimestamp for the duration
            // Verify that the provided metadata of the datastore after sandwichTimestamp (sandwich[1])
            // agrees with the stored hash
            require(
                dlsm.getDataStoreHashesForDurationAtTimestamp(duration, sandwich[1].timestamp, sandwich[1].index)
                    == DataStoreUtils.computeDataStoreHash(sandwich[1].metadata),
                "DataLayrBombVerifier.verifyDataStoreIdSandwich: sandwich[1].metadata preimage is incorrect"
            );

            //make sure that sandwich[0] and sandwich[1] are consecutive datastores for the duration by checking that their
            //durationDataStoreIds are consecutive
            require(
                sandwich[0].metadata.durationDataStoreId + 1 == sandwich[1].metadata.durationDataStoreId,
                "DataLayrBombVerifier.verifyDataStoreIdSandwich: x and y datastore must be incremental or y datastore is not first in the duration"
            );
        } else {
            //if sandwich[1].timestamp, the prover is claiming there is no datastore after sandwichTimestamp for the duration
            require(
                dlsm.totalDataStoresForDuration(duration) == sandwich[0].metadata.durationDataStoreId,
                "DataLayrBombVerifier.verifyDataStoreIdSandwich: x datastore is not the last datastore in the duration or no datastores for duration"
            );
        }
        return sandwich[1].metadata;
    }

    // inputs are a pseudo-random 'offset' value and an array of the number of active DataStores, ordered by duration
    // given the 'offset' value, this function moves through the 'duration' bins, and returns the bin and offset *within that bin* corresponding to 'offset'
    // in other words, it finds the position for the 'offset'-th entry, specified by a duration 'bin' and a value corresponding to a specific DataStore within that bin
    //
    // given an ordered list of groups and the number of elements in each group, given an offset, calculate which group and index within the group the offset points to
    function calculateCorrectIndexAndDurationOffsetFromNumberActiveDataStoresForDuration(
        uint32 offset,
        uint32[] memory numberActiveDataStoresForDuration
    )
        internal
        pure
        returns (uint8, uint32)
    {
        uint32 offsetLeft = offset;
        uint256 i = 0;
        for (; i < numberActiveDataStoresForDuration.length; ++i) {
            //we use > not >= because offsetLeft should be the index within the correct duration
            if (numberActiveDataStoresForDuration[i] > offsetLeft) {
                break;
            }
            offsetLeft -= numberActiveDataStoresForDuration[i];
        }

        return (uint8(i), offsetLeft);
    }

    function getChunkNumber(
        address operator,
        uint32 operatorIndex,
        uint32 totalOperatorsIndex,
        IDataLayrServiceManager.DataStoreSearchData calldata searchData
    )
        internal
        view
        returns (uint32)
    {
        /**
         * Get information on the dataStore for which disperser is being challenged. This dataStore was
         * constructed during call to initDataStore in DataLayr.sol by the disperser.
         */

        require(
            dlsm.getDataStoreHashesForDurationAtTimestamp(searchData.duration, searchData.timestamp, searchData.index)
                == DataStoreUtils.computeDataStoreHash(searchData.metadata),
            "search.metadataclear preimage is incorrect"
        );

        // check that disperser had acquire quorum for this dataStore
        require(searchData.metadata.signatoryRecordHash != bytes32(0), "Datastore is not committed yet");

        operatorIndex = dlRegistry.getOperatorIndex(operator, searchData.metadata.blockNumber, operatorIndex);

        totalOperatorsIndex = dlRegistry.getTotalOperators(searchData.metadata.blockNumber, totalOperatorsIndex);
        return (operatorIndex + searchData.metadata.globalDataStoreId) % totalOperatorsIndex;
    }

    function nonInteractivePolynomialProof(
        address operator,
        uint32 operatorIndex,
        uint32 totalOperatorsIndex,
        uint32 dataStoreId,
        DisclosureProof calldata disclosureProof,
        IDataLayrServiceManager.DataStoreSearchData calldata searchData
    )
        internal
        view
        returns (bool)
    {
        uint32 chunkNumber = getChunkNumber(operator, operatorIndex, totalOperatorsIndex, searchData);
        require(
            searchData.metadata.globalDataStoreId == dataStoreId,
            "DataLayrBombVerifier.nonInteractivePolynomialProof: searchData does not match provided dataStoreId"
        );
        require(
            searchData.metadata.headerHash == keccak256(disclosureProof.header),
            "DataLayrBombVerifier.nonInteractivePolynomialProof: hash of dislosure proof header does not match provided searchData"
        );
        bool res = challengeUtils.nonInteractivePolynomialProof(
            disclosureProof.header,
            chunkNumber,
            disclosureProof.poly,
            disclosureProof.multiRevealProof,
            disclosureProof.polyEquivalenceProof
        );

        return res;
    }

    function verifyMetadataPreImage(IDataLayrServiceManager.DataStoreSearchData calldata searchData)
        internal
        view
        returns (bool)
    {
        return dlsm.getDataStoreHashesForDurationAtTimestamp(
            searchData.duration, searchData.timestamp, searchData.index
        ) == DataStoreUtils.computeDataStoreHash(searchData.metadata);
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return x > y ? x : y;
    }
}
