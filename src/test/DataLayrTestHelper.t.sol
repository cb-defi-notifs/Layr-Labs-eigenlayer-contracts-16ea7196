// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../contracts/libraries/BytesLib.sol";
import "../test/Deployer.t.sol";
import "../test/TestHelper.t.sol";


contract DataLayrTestHelper is EigenLayrDeployer, TestHelper {
    using BytesLib for bytes;

    /// @dev ensure that operator has been delegated to by calling _testInitiateDelegation
    function _testRegisterOperatorWithDataLayr(
        uint8 operatorIndex,
        uint8 operatorType,
        bytes32 ephemeralKeyHash,
        string memory socket
    ) public {

        address operator = getOperatorAddress(operatorIndex);

        cheats.startPrank(operator);
        dlReg.registerOperator(operatorType, 
            ephemeralKeyHash, 
            keccak256(abi.encodePacked(uint256(ephemeralKeyHash) | 1234567876543)), 
            getOperatorPubkeyG1(operatorIndex), 
            socket
        );
        cheats.stopPrank();

    }

    function _testDeregisterOperatorWithDataLayr(
        uint8 operatorIndex,
        uint8 operatorListIndex
    ) public {

        address operator = getOperatorAddress(operatorIndex);

        cheats.startPrank(operator);
        dlReg.deregisterOperator(getOperatorPubkeyG1(operatorIndex), operatorListIndex);
        cheats.stopPrank();
    }
    //initiates a data store
    //checks that the dataStoreId, initTime, storePeriodLength, and committed status are all correct
   //initiates a data store
    //checks that the dataStoreId, initTime, storePeriodLength, and committed status are all correct
   function _testInitDataStore(uint256 initTimestamp, address confirmer, bytes memory header)
        internal
        returns (IDataLayrServiceManager.DataStoreSearchData memory searchData)
    {        
        // weth is set as the paymentToken of dlsm, so we must approve dlsm to transfer weth
        weth.transfer(storer, 1e11);
        cheats.startPrank(storer);
        weth.approve(address(dataLayrPaymentManager), type(uint256).max);

        dataLayrPaymentManager.depositFutureFees(storer, 1e11);

        uint32 referenceBlockNumber = uint32(block.number);
        uint32 blockNumber = uint32(block.number);
        uint32 totalOperatorsIndex = uint32(dlReg.getLengthOfTotalOperatorsHistory() - 1);

        require(initTimestamp >= block.timestamp, "_testInitDataStore: warping back in time!");
        cheats.warp(initTimestamp);
        uint256 timestamp = block.timestamp;

        uint32 index = dlsm.initDataStore(
            storer,
            confirmer,
            durationToInit,
            referenceBlockNumber,
            totalOperatorsIndex,
            header
        );

        bytes32 headerHash = keccak256(header);

        cheats.stopPrank();

        uint32 totalOperators = dlReg.getTotalOperators(blockNumber, totalOperatorsIndex);
        uint32 degree;
        assembly{
            degree := shr(224, mload(add(header, 96)))
        }
        uint256 totalBytes = totalOperators * (degree + 1) * 31;
        
        uint256 fee = dlsm.calculateFee(totalBytes, 1, uint32(durationToInit*DURATION_SCALE));



        IDataLayrServiceManager.DataStoreMetadata
            memory metadata = IDataLayrServiceManager.DataStoreMetadata({
                headerHash: headerHash,
                durationDataStoreId: dlsm.getNumDataStoresForDuration(durationToInit) - 1,
                globalDataStoreId: dlsm.taskNumber() - 1,
                referenceBlockNumber: referenceBlockNumber,
                blockNumber: blockNumber,
                fee: uint96(fee),
                confirmer: confirmer,
                signatoryRecordHash: bytes32(0)
            });

        {
            bytes32 dataStoreHash = DataStoreUtils.computeDataStoreHash(metadata);

            //check if computed hash matches stored hash in DLSM
            assertTrue(
                dataStoreHash ==
                    dlsm.getDataStoreHashesForDurationAtTimestamp(durationToInit, timestamp, index),
                "dataStore hashes do not match"
            );
        }
        
        searchData = IDataLayrServiceManager.DataStoreSearchData({
                metadata: metadata,
                duration: durationToInit,
                timestamp: timestamp,
                index: index
            });
        return searchData;
    }

    //commits data store to data layer
    function _testCommitDataStore(
        bytes32 msgHash,
        uint32 numberOfNonSigners,
        uint256[] memory apk,
        uint256[] memory sigma,
        uint32 blockNumber,
        uint32 dataStoreId,
        IDataLayrServiceManager.DataStoreSearchData memory searchData
    )
        internal
    {
        /**
         * @param data This calldata is of the format:
         * <
         * bytes32 headerHash,
         * uint48 index of the totalStake corresponding to the dataStoreId in the 'totalStakeHistory' array of the BLSRegistryWithBomb
         * uint32 blockNumber
         * uint32 dataStoreId
         * uint32 numberOfNonSigners,
         * uint256[numberOfSigners][4] pubkeys of nonsigners,
         * uint32 apkIndex,
         * uint256[4] apk,
         * uint256[2] sigma
         * >
         */

        bytes memory data = abi.encodePacked(
            msgHash,
            uint48(dlReg.getLengthOfTotalStakeHistory() - 1),
            blockNumber,
            dataStoreId,
            numberOfNonSigners,
            // no pubkeys here since zero nonSigners for now
            uint32(dlReg.getApkUpdatesLength() - 1),
            apk[0],
            apk[1],
            apk[2],
            apk[3],
            sigma[0],
            sigma[1]
        );

        dlsm.confirmDataStore(data, searchData);
    }

    function _testRegisterBLSPubKey(
        uint8 operatorIndex
    ) public {
        address operator = getOperatorAddress(operatorIndex);

        cheats.startPrank(operator);
        //whitelist the dlsm to slash the operator
        slasher.optIntoSlashing(address(dlsm));
        (uint256 s, BN254.G1Point memory rPoint) = getOperatorSchnorrSignature(operatorIndex);
        pubkeyCompendium.registerBLSPublicKey(s, rPoint, getOperatorPubkeyG1(operatorIndex), getOperatorPubkeyG2(operatorIndex));
        cheats.stopPrank();
    }

    /**
     * @param numberOfSigners is the number of signers in the quorum of DLNs
     * @param includeOperator is a boolean that indicates whether or not we want to also register
     * the operator no. 0, for test case where they are not already registered as a delegator.
     *
     */
    function _testRegisterSigners(uint32 numberOfSigners, bool includeOperator) internal {
        uint256 start = 1;
        if (includeOperator) {
            start = 0;
        }

        //register all the operators
        //skip i = 0 since we have already registered getOperatorAddress(0) !!
        for (uint256 i = start; i < numberOfSigners; ++i) {
            _testRegisterAdditionalSelfOperator(i);
        }
    }

    function _testRegisterAdditionalSelfOperator(uint256 index) internal {
        address sender = getOperatorAddress(index);
        bytes32 ephemeralKeyHash = ephemeralKeyHashes[index];
        //register as both ETH and EIGEN operator
        uint8 operatorType = 3;
        uint256 wethToDeposit = 1e18;
        uint256 eigenToDeposit = 1e10;
        _testWethDeposit(sender, wethToDeposit);
        _testDepositEigen(sender, eigenToDeposit);
        _testRegisterAsOperator(sender, IDelegationTerms(sender));
        string memory socket = "255.255.255.255";

        cheats.startPrank(sender);

        //whitelist the dlsm to slash the operator
        slasher.optIntoSlashing(address(dlsm));

        (uint256 s, BN254.G1Point memory rPoint) = getOperatorSchnorrSignature(index);
        pubkeyCompendium.registerBLSPublicKey(s, rPoint, getOperatorPubkeyG1(index), getOperatorPubkeyG2(index));
        dlReg.registerOperator(
            operatorType, 
            ephemeralKeyHash, 
            keccak256(abi.encodePacked(uint256(ephemeralKeyHash) | 1234567876543)), 
            getOperatorPubkeyG1(index), 
            socket
        );

        cheats.stopPrank();

        // verify that registration was stored correctly
        if ((operatorType & 1) == 1 && wethToDeposit > dlReg.minimumStakeFirstQuorum()) {
            assertTrue(dlReg.firstQuorumStakedByOperator(sender) == wethToDeposit, "ethStaked not increased!");
        } else {
            assertTrue(dlReg.firstQuorumStakedByOperator(sender) == 0, "ethStaked incorrectly > 0");
        }
        if ((operatorType & 2) == 2 && eigenToDeposit > dlReg.minimumStakeSecondQuorum()) {
            assertTrue(dlReg.secondQuorumStakedByOperator(sender) == eigenToDeposit, "eigenStaked not increased!");
        } else {
            assertTrue(dlReg.secondQuorumStakedByOperator(sender) == 0, "eigenStaked incorrectly > 0");
        }
    }

    // second return value is the complete `searchData` that can serve as an input to `stakeWithdrawalVerification`
    function _testConfirmDataStoreSelfOperators(uint8 numSigners)
        internal
        returns (bytes memory, IDataLayrServiceManager.DataStoreSearchData memory)
    {
        cheats.assume(numSigners > 0 && numSigners <= 15);

        //register all the operators
        for (uint256 i = 0; i < numSigners; ++i) {
            _testRegisterAdditionalSelfOperator(i);
        }

        // hard-coded values
        uint256 index = 0;
        /**
         * this value *must be the initTime* since the initTime is included in the calcuation of the `msgHash`,
         *  and the signatures (which we have coded in) are signatures of the `msgHash`, assuming this exact value.
         */
        uint256 initTime = 1000000001;

        return _testConfirmDataStoreWithoutRegister(initTime, index, numSigners);
    }

    function _testConfirmDataStoreWithoutRegister(uint256 initTime, uint256 index, uint8 numSigners)
        internal
        returns (bytes memory, IDataLayrServiceManager.DataStoreSearchData memory)
    {
        IDataLayrServiceManager.DataStoreSearchData memory searchData = _testInitDataStore(initTime, address(this), header);

        uint32 numberOfNonSigners = 0;
        uint256[2] memory apkG1;
        uint256[4] memory apkG2;
        {
            (apkG1[0], apkG1[1]) = getAggregatePublicKeyG1();
            (apkG2[0], apkG2[1], apkG2[2], apkG2[3]) = getAggregatePublicKeyG2();
        }

        (uint256 sigma_0, uint256 sigma_1) = getAggSignature(); //(signatureData[index*2], signatureData[2*index + 1]);

        /**
         * @param data This calldata is of the format:
         * <
         * bytes32 msgHash,
         * uint48 index of the totalStake corresponding to the dataStoreId in the 'totalStakeHistory' array of the BLSRegistryWithBomb
         * uint32 blockNumber
         * uint32 dataStoreId
         * uint32 numberOfNonSigners,
         * uint256[numberOfNonSigners][4] pubkeys of nonsigners,
         * uint32 apkIndex,
         * uint256[4] apk,
         * uint256[2] sigma
         * >
         */
        
        
        emit log_named_bytes32("MSG HASH", 
            keccak256(
                abi.encodePacked(
                    searchData.metadata.globalDataStoreId,
                    searchData.metadata.headerHash,
                    searchData.duration,
                    initTime,
                    searchData.index
                )
            ));

        bytes memory data = abi.encodePacked(
            keccak256(
                abi.encodePacked(
                    searchData.metadata.globalDataStoreId,
                    searchData.metadata.headerHash,
                    searchData.duration,
                    initTime,
                    searchData.index
                )
            ),
            uint48(dlReg.getLengthOfTotalStakeHistory() - 1),
            searchData.metadata.referenceBlockNumber,
            searchData.metadata.globalDataStoreId,
            numberOfNonSigners,
            // no pubkeys here since zero nonSigners for now
            uint32(dlReg.getApkUpdatesLength() - 1),
            apkG1[0],
            apkG1[1],
            apkG2[0],
            apkG2[1],
            apkG2[2],
            apkG2[3],
            sigma_0,
            sigma_1
        );

        // get the signatoryRecordHash that will result from the `confirmDataStore` call (this is used in modifying the dataStoreHash post-confirmation)
        bytes32 signatoryRecordHash;
        (
            // uint32 dataStoreIdToConfirm,
            // uint32 blockNumberFromTaskHash,
            // bytes32 msgHash,
            // SignatoryTotals memory signedTotals,
            // bytes32 signatoryRecordHash
            ,
            ,
            ,
            ,
            signatoryRecordHash
        ) = dlsm.checkSignatures(data);

        uint256 gasbefore = gasleft();
        dlsm.confirmDataStore(data, searchData);
        emit log_named_uint("confirm gas overall", gasbefore - gasleft());
        cheats.stopPrank();
        // bytes32 sighash = dlsm.getDataStoreIdSignatureHash(
        //     dlsm.dataStoreId() - 1
        // );
        // assertTrue(sighash != bytes32(0), "Data store not committed");

        /**
         * Copy the signatoryRecordHash to the `searchData` struct, so the `searchData` can now be used in `stakeWithdrawalVerification` calls appropriately
         * This must be done *after* the call to `dlsm.confirmDataStore`, since the appropriate `searchData` changes as a result of this call
         */
        searchData.metadata.signatoryRecordHash = signatoryRecordHash;

        return (data, searchData);
    }


    //Internal function for assembling calldata - prevents stack too deep errors
    function _getOneNonSignerCallData(
        bytes32 msgHash,
        uint32 numberOfNonSigners,
        RegistrantAPKG2 memory registrantApkG2,
        RegistrantAPKG1 memory registrantApkG1,
        SignerAggSig memory signerAggSig,
        NonSignerPK memory nonSignerPK,
        uint32 blockNumber,
        uint32 dataStoreId
    )
        internal
        view
        returns (bytes memory)
    {
        /**
         * @param data This calldata is of the format:
         * <
         * bytes32 msgHash,
         * uint48 index of the totalStake corresponding to the dataStoreId in the 'totalStakeHistory' array of the BLSRegistryWithBomb
         * uint32 blockNumber
         * uint32 dataStoreId
         * uint32 numberOfNonSigners,
         * uint256[numberOfSigners][4] pubkeys of nonsigners,
         * uint32 stakeIndex
         * uint32 apkIndex,
         * uint256[4] apk,
         * uint256[2] sigma
         * >s
         */
        bytes memory data = abi.encodePacked(
            msgHash,
            uint48(dlReg.getLengthOfTotalStakeHistory() - 1),
            blockNumber,
            dataStoreId,
            numberOfNonSigners,
            nonSignerPK.x,
            nonSignerPK.y
        );

        data = abi.encodePacked(
            data,
            uint32(0),
            //nonSignerPK.stakeIndex,
            uint32(dlReg.getApkUpdatesLength() - 1),
            registrantApkG1.apk0,
            registrantApkG1.apk1
        );

        data = abi.encodePacked(
            data,
            registrantApkG2.apk0,
            registrantApkG2.apk1,
            registrantApkG2.apk2,
            registrantApkG2.apk3,
            signerAggSig.sigma0,
            signerAggSig.sigma1
        );

        return data;
    }

    function _testInitDataStoreExpectRevert(
        uint256 initTimestamp, 
        address confirmer, 
        bytes memory header, 
        bytes memory revertMsg
    )
        internal
    {        
        // weth is set as the paymentToken of dlsm, so we must approve dlsm to transfer weth
        // weth is set as the paymentToken of dlsm, so we must approve dlsm to transfer weth
        weth.transfer(storer, 1e11);
        cheats.startPrank(storer);
        weth.approve(address(dataLayrPaymentManager), type(uint256).max);

        dataLayrPaymentManager.depositFutureFees(storer, 1e11);

        uint32 blockNumber = uint32(block.number);
        uint32 totalOperatorsIndex = uint32(dlReg.getLengthOfTotalOperatorsHistory() - 1);

        require(initTimestamp >= block.timestamp, "_testInitDataStore: warping back in time!");
        cheats.warp(initTimestamp);

        cheats.expectRevert(revertMsg);
        dlsm.initDataStore(
            storer,
            confirmer,
            durationToInit,
            blockNumber,
            totalOperatorsIndex,
            header
        );
    }




}


