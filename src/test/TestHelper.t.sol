// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../contracts/libraries/BytesLib.sol";
import "../test/Deployer.t.sol";


contract TestHelper is EigenLayrDeployer {
    using BytesLib for bytes;

    uint8 durationToInit = 2;

    function _testInitiateDelegation(
        uint8 operatorIndex,
        uint256 amountEigenToDeposit, 
        uint256 amountEthToDeposit        
    )
        public returns (uint256 amountEthStaked, uint256 amountEigenStaked)
    {
        address operator = signers[operatorIndex];
        //setting up operator's delegation terms
        weth.transfer(operator, 1e18);
        weth.transfer(_challenger, 1e18);
        _testRegisterAsOperator(operator, IDelegationTerms(operator));

        for (uint256 i; i < delegates.length; i++) {
            //initialize weth, eigen and eth balances for delegator
            eigenToken.transfer(delegates[i], amountEigenToDeposit);
            weth.transfer(delegates[i], amountEthToDeposit);
            cheats.deal(delegates[i], amountEthToDeposit);

            cheats.startPrank(delegates[i]);

            //deposit delegator's eigen into investment manager
            eigenToken.approve(address(investmentManager), type(uint256).max);

            investmentManager.depositIntoStrategy(eigenStrat, eigenToken, amountEigenToDeposit);

            //deposit weth into investment manager
            weth.approve(address(investmentManager), type(uint256).max);
            investmentManager.depositIntoStrategy(wethStrat, weth, amountEthToDeposit);
            cheats.stopPrank();

            uint256 operatorEigenSharesBefore = delegation.operatorShares(operator, eigenStrat);
            uint256 operatorWETHSharesBefore = delegation.operatorShares(operator, wethStrat);


            //delegate delegator's deposits to operator
            _testDelegateToOperator(delegates[i], operator);
            //testing to see if increaseOperatorShares worked
            assertTrue(
                delegation.operatorShares(operator, eigenStrat) - operatorEigenSharesBefore == amountEigenToDeposit
            );
            assertTrue(delegation.operatorShares(operator, wethStrat) - operatorWETHSharesBefore == amountEthToDeposit);
            
        }
        amountEthStaked += delegation.operatorShares(operator, wethStrat);
        amountEigenStaked += delegation.operatorShares(operator, eigenStrat);

        return (amountEthStaked, amountEigenStaked);
    }

    function _testRegisterBLSPubKey(
        uint8 operatorIndex
    ) public {
        address operator = signers[operatorIndex];

        cheats.startPrank(operator);
        //whitelist the dlsm to slash the operator
        slasher.allowToSlash(address(dlsm));
        pubkeyCompendium.registerBLSPublicKey(registrationData[operatorIndex]);
        cheats.stopPrank();
    }


    /// @dev ensure that operator has been delegated to by calling _testInitiateDelegation
    function _testRegisterOperatorWithDataLayr(
        uint8 operatorIndex,
        uint8 operatorType,
        bytes32 ephemeralKey,
        string memory socket
    ) public {

        address operator = signers[operatorIndex];

        cheats.startPrank(operator);
        dlReg.registerOperator(operatorType, ephemeralKey, registrationData[operatorIndex].slice(0, 128), socket);
        cheats.stopPrank();

    }

    function _testDeregisterOperatorWithDataLayr(
        uint8 operatorIndex,
        uint256[4] memory pubkeyToRemoveAff,
        uint8 operatorListIndex,
        bytes32 finalEphemeralKey
    ) public {

        address operator = signers[operatorIndex];

        cheats.startPrank(operator);
        dlReg.deregisterOperator(pubkeyToRemoveAff, operatorListIndex, finalEphemeralKey);
        cheats.stopPrank();
    }


    //initiates a data store
    //checks that the dataStoreId, initTime, storePeriodLength, and committed status are all correct
   function _testInitDataStore(uint256 initTimestamp, address confirmer)
        internal
        returns (IDataLayrServiceManager.DataStoreSearchData memory searchData)
    {
        bytes memory header = abi.encodePacked(
            hex"010203040506070809101112131415160102030405060708091011121314151601020304050607080910111213141516010203040506070809101112131415160000000400000004"
        );
        uint32 totalBytes = 1e6;

        // weth is set as the paymentToken of dlsm, so we must approve dlsm to transfer weth
        weth.transfer(storer, 1e11);
        cheats.startPrank(storer);
        weth.approve(address(dataLayrPaymentManager), type(uint256).max);

        dataLayrPaymentManager.depositFutureFees(storer, 1e11);

        uint32 blockNumber = uint32(block.number);

        require(initTimestamp >= block.timestamp, "_testInitDataStore: warping back in time!");
        cheats.warp(initTimestamp);
        uint256 timestamp = block.timestamp;

        uint32 index = dlsm.initDataStore(
            storer,
            confirmer,
            header,
            durationToInit,
            blockNumber
        );

        bytes32 headerHash = keccak256(header);

        cheats.stopPrank();

        uint256 fee = calculateFee(totalBytes, 1, durationToInit);

        IDataLayrServiceManager.DataStoreMetadata
            memory metadata = IDataLayrServiceManager.DataStoreMetadata({
                headerHash: headerHash,
                durationDataStoreId: dlsm.getNumDataStoresForDuration(durationToInit) - 1,
                globalDataStoreId: dlsm.taskNumber() - 1,
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
        //skip i = 0 since we have already registered signers[0] !!
        for (uint256 i = start; i < numberOfSigners; ++i) {
            _testRegisterAdditionalSelfOperator(signers[i], registrationData[i], ephemeralKeyHashes[i]);
        }
    }

    //Internal function for assembling calldata - prevents stack too deep errors
    function _getCallData(
        bytes32 msgHash,
        uint32 numberOfNonSigners,
        signerInfo memory signers,
        nonSignerInfo memory nonsigners,
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
            nonsigners.xA0,
            nonsigners.xA1,
            nonsigners.yA0,
            nonsigners.yA1
        );

        data = abi.encodePacked(
            data,
            uint32(0),
            uint32(dlReg.getApkUpdatesLength() - 1),
            signers.apk0,
            signers.apk1,
            signers.apk2,
            signers.apk3,
            signers.sigma0,
            signers.sigma1
        );

        return data;
    }

    /**
     * @notice Deposits `amountToDeposit` of WETH from address `sender` into `wethStrat`.
     * @param sender The address to spoof calls from using `cheats.startPrank(sender)`
     * @param amountToDeposit Amount of WETH that is first *transferred from this contract to `sender`* and then deposited by `sender` into `stratToDepositTo`
     */
    function _testWethDeposit(address sender, uint256 amountToDeposit) internal returns (uint256 amountDeposited) {
        cheats.assume(amountToDeposit <= wethInitialSupply);
        // transfer WETH to `sender` and have them deposit it into `strat`
        amountDeposited = _testDepositToStrategy(sender, amountToDeposit, weth, wethStrat);
    }

    /**
     * @notice Deposits `amountToDeposit` of EIGEN from address `sender` into `eigenStrat`.
     * @param sender The address to spoof calls from using `cheats.startPrank(sender)`
     * @param amountToDeposit Amount of EIGEN that is first *transferred from this contract to `sender`* and then deposited by `sender` into `stratToDepositTo`
     */
    function _testDepositEigen(address sender, uint256 amountToDeposit) public {
        _testDepositToStrategy(sender, amountToDeposit, eigenToken, eigenStrat);
    }

    /**
     * @notice Deposits `amountToDeposit` of `underlyingToken` from address `sender` into `stratToDepositTo`.
     * *If*  `sender` has zero shares prior to deposit, *then* checks that `stratToDepositTo` is correctly added to their `investorStrats` array.
     *
     * @param sender The address to spoof calls from using `cheats.startPrank(sender)`
     * @param amountToDeposit Amount of WETH that is first *transferred from this contract to `sender`* and then deposited by `sender` into `stratToDepositTo`
     */
    function _testDepositToStrategy(
        address sender,
        uint256 amountToDeposit,
        IERC20 underlyingToken,
        IInvestmentStrategy stratToDepositTo
    )
        internal
        returns (uint256 amountDeposited)
    {
        // deposits will revert when amountToDeposit is 0
        cheats.assume(amountToDeposit > 0);

        uint256 operatorSharesBefore = investmentManager.investorStratShares(sender, stratToDepositTo);
        // assumes this contract already has the underlying token!
        uint256 contractBalance = underlyingToken.balanceOf(address(this));
        // logging and error for misusing this function (see assumption above)
        if (amountToDeposit > contractBalance) {
            emit log("amountToDeposit > contractBalance");
            emit log_named_uint("amountToDeposit is", amountToDeposit);
            emit log_named_uint("while contractBalance is", contractBalance);
            revert("_testDepositToStrategy failure");
        } else {

            
            underlyingToken.transfer(sender, amountToDeposit);
            cheats.startPrank(sender);
            underlyingToken.approve(address(investmentManager), type(uint256).max);

            investmentManager.depositIntoStrategy(stratToDepositTo, underlyingToken, amountToDeposit);
            amountDeposited = amountToDeposit;

            //check if depositor has never used this strat, that it is added correctly to investorStrats array.
            if (operatorSharesBefore == 0) {
                // check that strategy is appropriately added to dynamic array of all of sender's strategies
                assertTrue(
                    investmentManager.investorStrats(sender, investmentManager.investorStratsLength(sender) - 1)
                        == stratToDepositTo,
                    "_depositToStrategy: investorStrats array updated incorrectly"
                );
            }

            
            


            //in this case, since shares never grow, the shares should just match the deposited amount
            assertEq(
                investmentManager.investorStratShares(sender, stratToDepositTo) - operatorSharesBefore,
                amountDeposited,
                "_depositToStrategy: shares should match deposit"
            );
        }
        cheats.stopPrank();
    }

    //checks that it is possible to withdraw from the given `stratToWithdrawFrom`
    function _testWithdrawFromStrategy(
        address sender,
        uint256 strategyIndex,
        uint256 amountSharesToWithdraw,
        IERC20 underlyingToken,
        IInvestmentStrategy stratToWithdrawFrom
    )
        internal
    {
        // fetch the length of `sender`'s dynamic `investorStrats` array
        uint256 investorStratsLengthBefore = investmentManager.investorStratsLength(sender);
        // fetch `sender`'s existing share amount
        uint256 existingShares = investmentManager.investorStratShares(sender, stratToWithdrawFrom);
        // fetch `sender`'s existing balance of `underlyingToken`
        uint256 senderUnderlyingBalanceBefore = underlyingToken.balanceOf(sender);

        // sanity checks on `strategyIndex` input
        if (strategyIndex >= investorStratsLengthBefore) {
            emit log("_testWithdrawFromStrategy: attempting to withdraw from out-of-bounds index");
            revert("_testWithdrawFromStrategy: attempting to withdraw from out-of-bounds index");
        }
        assertEq(address(stratToWithdrawFrom), address(investmentManager.investorStrats(sender, strategyIndex)));

        cheats.prank(sender);
        //trying to withdraw more than the amountDeposited will fail, so we expect a revert and *short-circuit* if it happens
        if (amountSharesToWithdraw > existingShares) {
            cheats.expectRevert(bytes("InvestmentManager._removeShares: shareAmount too high"));
            investmentManager.withdrawFromStrategy(
                strategyIndex, stratToWithdrawFrom, underlyingToken, amountSharesToWithdraw
            );
            return;
        } else {
            investmentManager.withdrawFromStrategy(
                strategyIndex, stratToWithdrawFrom, underlyingToken, amountSharesToWithdraw
            );
        }

        uint256 senderUnderlyingBalanceAfter = underlyingToken.balanceOf(sender);

        assertEq(
            amountSharesToWithdraw,
            senderUnderlyingBalanceAfter - senderUnderlyingBalanceBefore,
            "_testWithdrawFromStrategy: shares differ from 1-to-1 with underlyingToken?"
        );
        cheats.stopPrank();
    }

    function _testRegisterAdditionalSelfOperator(address sender, bytes memory data, bytes32 ephemeralKeyHash) internal {
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
        slasher.allowToSlash(address(dlsm));

        pubkeyCompendium.registerBLSPublicKey(data);
        dlReg.registerOperator(operatorType, ephemeralKeyHash, data.slice(0, 128), socket);

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
            _testRegisterAdditionalSelfOperator(signers[i], registrationData[i], ephemeralKeyHashes[i]);
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
        IDataLayrServiceManager.DataStoreSearchData memory searchData = _testInitDataStore(initTime, address(this));

        uint32 numberOfNonSigners = 0;
        uint256[4] memory apk;
        {
            (apk[0], apk[1], apk[2], apk[3]) = getAggregatePublicKey(uint256(numSigners));
        }
        (uint256 sigma_0, uint256 sigma_1) = getSignature(uint256(numSigners), index); //(signatureData[index*2], signatureData[2*index + 1]);

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
            searchData.metadata.blockNumber,
            searchData.metadata.globalDataStoreId,
            numberOfNonSigners,
            // no pubkeys here since zero nonSigners for now
            uint32(dlReg.getApkUpdatesLength() - 1),
            apk[0],
            apk[1],
            apk[2],
            apk[3],
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

    // simply tries to register 'sender' as a delegate, setting their 'DelegationTerms' contract in EigenLayrDelegation to 'dt'
    // verifies that the storage of EigenLayrDelegation contract is updated appropriately
    function _testRegisterAsOperator(address sender, IDelegationTerms dt) internal {
        cheats.startPrank(sender);
        delegation.registerAsOperator(dt);
        assertTrue(delegation.isOperator(sender), "testRegisterAsOperator: sender is not a delegate");

        assertTrue(
            delegation.delegationTerms(sender) == dt, "_testRegisterAsOperator: delegationTerms not set appropriately"
        );

        assertTrue(delegation.isDelegated(sender), "_testRegisterAsOperator: sender not marked as actively delegated");
        cheats.stopPrank();
    }

    // tries to delegate from 'sender' to 'operator'
    // verifies that:
    //                  delegator has at least some shares
    //                  delegatedShares update correctly for 'operator'
    //                  delegated status is updated correctly for 'sender'
    function _testDelegateToOperator(address sender, address operator) internal {
        //delegator-specific information
        (IInvestmentStrategy[] memory delegateStrategies, uint256[] memory delegateShares) =
            investmentManager.getDeposits(sender);

        uint256 numStrats = delegateShares.length;
        assertTrue(numStrats > 0, "_testDelegateToOperator: delegating from address with no investments");
        uint256[] memory inititalSharesInStrats = new uint256[](numStrats);
        for (uint256 i = 0; i < numStrats; ++i) {
            inititalSharesInStrats[i] = delegation.operatorShares(operator, delegateStrategies[i]);
        }

        cheats.startPrank(sender);
        delegation.delegateTo(operator);
        cheats.stopPrank();

        assertTrue(
            delegation.delegation(sender) == operator,
            "_testDelegateToOperator: delegated address not set appropriately"
        );
        assertTrue(
            delegation.delegated(sender) == IEigenLayrDelegation.DelegationStatus.DELEGATED,
            "_testDelegateToOperator: delegated status not set appropriately"
        );

        for (uint256 i = 0; i < numStrats; ++i) {
            uint256 operatorSharesBefore = inititalSharesInStrats[i];
            uint256 operatorSharesAfter = delegation.operatorShares(operator, delegateStrategies[i]);
            assertTrue(
                operatorSharesAfter == (operatorSharesBefore + delegateShares[i]),
                "_testDelegateToOperator: delegatedShares not increased correctly"
            );
        }
    }

    // deploys a InvestmentStrategyBase contract and initializes it to treat `underlyingToken` as its underlying token
    function _testAddStrategyBase(IERC20 underlyingToken) internal returns (IInvestmentStrategy) {
        InvestmentStrategyBase strategy = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(baseStrategyImplementation),
                    address(eigenLayrProxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, underlyingToken, pauserReg)
                )
            )
        );
        return strategy;
    }

    // deploys 'numStratsToAdd' strategies using '_testAddStrategyBase' and then deposits 'amountToDeposit' to each of them from 'sender'
    function _testDepositStrategies(address sender, uint256 amountToDeposit, uint16 numStratsToAdd) internal {
        // hard-coded inputs
        uint96 multiplier = 1e18;
        IERC20 underlyingToken = weth;

        cheats.assume(numStratsToAdd > 0 && numStratsToAdd <= 20);
        IInvestmentStrategy[] memory stratsToDepositTo = new IInvestmentStrategy[](
                numStratsToAdd
            );
        for (uint16 i = 0; i < numStratsToAdd; ++i) {
            stratsToDepositTo[i] = _testAddStrategyBase(underlyingToken);
            _testDepositToStrategy(sender, amountToDeposit, weth, InvestmentStrategyBase(address(stratsToDepositTo[i])));
        }
        for (uint16 i = 0; i < numStratsToAdd; ++i) {
            // check that strategy is appropriately added to dynamic array of all of sender's strategies
            assertTrue(
                investmentManager.investorStrats(sender, i) == stratsToDepositTo[i],
                "investorStrats array updated incorrectly"
            );

            // TODO: perhaps remove this is we can. seems brittle if we don't track the number of strategies somewhere
            //store strategy in mapping of strategies
            strategies[i] = IInvestmentStrategy(address(stratsToDepositTo[i]));
        }
        // add strategies to dlRegistry
        for (uint16 i = 0; i < numStratsToAdd; ++i) {
            VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[] memory ethStratsAndMultipliers =
            new VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[](
                    1
                );
            ethStratsAndMultipliers[0].strategy = stratsToDepositTo[i];
            ethStratsAndMultipliers[0].multiplier = multiplier;
            dlReg.addStrategiesConsideredAndMultipliers(0, ethStratsAndMultipliers);
        }
    }

    function _testStartQueuedWithdrawalWaitingPeriod(
        address depositor,
        address withdrawer,
        bytes32 withdrawalRoot,
        uint32 stakeInactiveAfter
    ) internal {
        cheats.startPrank(withdrawer);
        // TODO: un-hardcode the '8 days' and '30 days' here
        // '8 days' accounts for the `REASONABLE_STAKES_UPDATE_PERIOD`
        cheats.warp(block.timestamp + 8 days);
        // '30 days' is used to prevent overflow in timestamps when stored as uint32 values (2^32 is in the year 2106 in UTC time)
        cheats.assume(stakeInactiveAfter < type(uint32).max - 30 days);
        cheats.assume(stakeInactiveAfter > block.timestamp);
        investmentManager.startQueuedWithdrawalWaitingPeriod(
                                        depositor, 
                                        withdrawalRoot, 
                                        stakeInactiveAfter
                                    );
        cheats.stopPrank();
    }

    function getG2PublicKeyHash(bytes calldata data, address signer) public view returns(bytes32 pkHash){

        uint256[4] memory pk;
        // verify sig of public key and get pubkeyHash back, slice out compressed apk
        (pk[0], pk[1], pk[2], pk[3]) = BLS.verifyBLSSigOfPubKeyHash(data, signer);

        pkHash = keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3]));

        return pkHash;

    }
}

