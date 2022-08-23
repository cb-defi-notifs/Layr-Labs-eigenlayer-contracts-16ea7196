// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Deployer.t.sol";
import "../contracts/investment/InvestmentManagerStorage.sol";


contract InvestmentTests is
    EigenLayrDeployer
{
    /**
     * @notice Verifies that it is possible to deposit WETH
     * @param amountToDeposit Fuzzed input for amount of WETH to deposit
     */
    function testWethDeposit(uint256 amountToDeposit)
        public
        returns (uint256 amountDeposited)
    {
        return _testWethDeposit(signers[0], amountToDeposit);
    }

    /**
     * @notice Verifies that it is possible to withdraw WETH after depositing it
     * 
     */
    function testWethWithdrawal(
        uint96 amountToDeposit,
        uint96 amountToWithdraw
    ) public {
        cheats.assume(amountToDeposit > 0);
        cheats.assume(amountToWithdraw > 0);
        address sender = signers[0];
        _testDepositToStrategy(sender, amountToDeposit, weth, strat);
        uint256 strategyIndex = 0;
        _testWithdrawFromStrategy(sender, strategyIndex, amountToWithdraw, weth, strat);
    }

    // verifies that a strategy gets removed from the dynamic array 'investorStrats' when the user no longer has any shares in the strategy
    function testRemovalOfStrategyOnWithdrawal(uint96 amountToDeposit) public {
        cheats.assume(amountToDeposit > 0);

        // hard-coded inputs
        IInvestmentStrategy _strat = strat;
        IERC20 underlyingToken = weth;
        address sender = signers[0];

        _testDepositToStrategy(sender, amountToDeposit, underlyingToken, _strat);
        uint256 investorStratsLengthBefore = investmentManager.investorStratsLength(sender);
        uint256 investorSharesBefore = investmentManager.investorStratShares(sender, _strat);
        _testWithdrawFromStrategy(sender, 0, investorSharesBefore, underlyingToken, _strat);
        uint256 investorSharesAfter = investmentManager.investorStratShares(sender, _strat);
        uint256 investorStratsLengthAfter = investmentManager.investorStratsLength(sender);
        assertEq(investorSharesAfter, 0, "testRemovalOfStrategyOnWithdrawal: did not remove all shares!");
        assertEq(investorStratsLengthBefore - investorStratsLengthAfter, 1, "testRemovalOfStrategyOnWithdrawal: strategy not removed from dynamic array when it should be");
    }


    //testing queued withdrawals in the investment manager
    function testQueuedWithdrawal(
        // uint256 amountToDeposit
        // ,uint256 amountToWithdraw 
    ) public {
        // harcoded inputs
        address[2] memory  accounts = [acct_0, acct_1];
        uint256[2] memory depositAmounts;
        uint256 amountToDeposit = 10e7;
        uint256 amountToWithdraw = 10e7;
        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        strategyArray[0] = strat;
        tokensArray[0] = weth;

        // we do this here to ensure that `acct_1` is delegated
        _testRegisterAsDelegate(acct_1, IDelegationTerms(acct_1));

        //make deposits in WETH strategy
        for (uint i=0; i<accounts.length; i++){
            // uint256 amountDeposited = _testWethDeposit(accounts[i], amountToDeposit);
            _testWethDeposit(accounts[i], amountToDeposit);
            depositAmounts[i] = amountToWithdraw;
        }
        //queue the withdrawal
        for (uint i=0; i<accounts.length; i++){ 
            cheats.startPrank(accounts[i]);

            uint256[] memory shareAmounts = new uint256[](1);
            shareAmounts[0] = depositAmounts[i];

            uint256[] memory strategyIndexes = new uint256[](1);
            strategyIndexes[0] = 0;

            InvestmentManagerStorage.WithdrawerAndNonce memory withdrawerAndNonce = InvestmentManagerStorage.WithdrawerAndNonce(accounts[i], 0);
            investmentManager.queueWithdrawal(strategyIndexes, strategyArray, tokensArray, shareAmounts, withdrawerAndNonce);
            if (delegation.isDelegated(accounts[i])) {
                assertTrue(
                    !investmentManager.canCompleteQueuedWithdrawal(strategyArray, tokensArray, shareAmounts, accounts[i], withdrawerAndNonce),
                    "testQueuedWithdrawal: user can immediately complete queued withdrawal (before waiting for fraudproof period), depsite being delegated"
                );
                cheats.expectRevert("withdrawal waiting period has not yet passed and depositor is still delegated");
            } else {
                assertTrue(
                    investmentManager.canCompleteQueuedWithdrawal(strategyArray, tokensArray, shareAmounts, accounts[i], withdrawerAndNonce),
                    "testQueuedWithdrawal: user *cannot* immediately complete queued withdrawal (before waiting for fraudproof period), despite *not* being delegated"
                );
            }
            investmentManager.completeQueuedWithdrawal(strategyArray, tokensArray, shareAmounts, accounts[i], withdrawerAndNonce);
            cheats.stopPrank();
        }
    }

    //testing queued withdrawals in the investment manager
    function testFraudproofQueuedWithdrawal(
        // uint256 amountToDeposit
        // ,uint256 amountToWithdraw 
    ) public {
        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        uint256[] memory strategyIndexes = new uint256[](1);

        // hardcoded input
        address sender = acct_0;
        {
            // hardcoded inputs
            uint256 amountToDeposit = 10e7;
            uint256 amountToWithdraw = 1e6;
            strategyArray[0] = strat;
            tokensArray[0] = weth;
            shareAmounts[0] = amountToWithdraw;
            strategyIndexes[0] = 0;

            // have `sender` deposit `amountToDeposit` of WETH
            uint256 amountDeposited = _testWethDeposit(sender, amountToDeposit);
            assertTrue(amountDeposited != 0, "testFraudproofQueuedWithdrawal: amountDeposited == 0");
        }

        // copied input from `_testConfirmDataStoreSelfOperators` -- test fails unless I do this
        uint256 initTime = 1000000001;
        cheats.warp(initTime);

        //queue the withdrawal    
        cheats.startPrank(sender);
        InvestmentManagerStorage.WithdrawerAndNonce memory withdrawerAndNonce = InvestmentManagerStorage.WithdrawerAndNonce(sender, 0);
        investmentManager.queueWithdrawal(strategyIndexes, strategyArray, tokensArray, shareAmounts, withdrawerAndNonce);
        cheats.stopPrank();

        // retrieve information about the queued withdrawal
        // bytes32 withdrawalRoot = investmentManager.calculateWithdrawalRoot(strategyArray, tokensArray, shareAmounts, withdrawerAndNonce);
        // (uint32 initTimestamp, uint32 latestFraudproofTimestamp, address withdrawer) = investmentManager.queuedWithdrawals(sender, withdrawalRoot);







        IDataLayrServiceManager.DataStoreSearchData memory searchData;
// BEGIN COPY PASTED CODE-BLOCK FROM `_testConfirmDataStoreSelfOperators`
{
        uint32 numberOfSigners = uint32(15);

        //register all the operators
        for (uint256 i = 0; i < numberOfSigners; ++i) {
            // emit log_named_uint("i", i);
            _testRegisterAdditionalSelfOperator(
                signers[i],
                registrationData[i]
            );
        }

        searchData = _testInitDataStore(initTime, address(this));

        uint32 numberOfNonSigners = 0;
        (uint256 apk_0, uint256 apk_1, uint256 apk_2, uint256 apk_3) = getAggregatePublicKey(uint256(numberOfSigners));

        (uint256 sigma_0, uint256 sigma_1) = getSignature(uint256(numberOfSigners), 0);//(signatureData[0], signatureData[1]);
        
        /** 
     @param data This calldata is of the format:
            <
             bytes32 msgHash,
             uint48 index of the totalStake corresponding to the dataStoreId in the 'totalStakeHistory' array of the BLSRegistryWithBomb
             uint32 blockNumber
             uint32 dataStoreId
             uint32 numberOfNonSigners,
             uint256[numberOfNonSigners][4] pubkeys of nonsigners,
             uint32 apkIndex,
             uint256[4] apk,
             uint256[2] sigma
            >
     */
        bytes memory data = abi.encodePacked(
            keccak256(abi.encodePacked(searchData.metadata.globalDataStoreId, searchData.metadata.headerHash, searchData.duration, initTime, uint32(0))),
            uint48(dlReg.getLengthOfTotalStakeHistory() - 1),
            searchData.metadata.blockNumber,
            searchData.metadata.globalDataStoreId,
            numberOfNonSigners,
            // no pubkeys here since zero nonSigners for now
            uint32(dlReg.getApkUpdatesLength() - 1),
            apk_0,
            apk_1,
            apk_2,
            apk_3,
            sigma_0,
            sigma_1
        );
        
        dlsm.confirmDataStore(data, searchData);
        cheats.stopPrank();
// END COPY PASTED CODE-BLOCK FROM `_testConfirmDataStoreSelfOperators`
}


    // //Relevant metadata for a given datastore
    // struct DataStoreMetadata {
    //     bytes32 headerHash;
    //     uint32 durationDataStoreId;
    //     uint32 globalDataStoreId;
    //     uint32 blockNumber;
    //     uint96 fee;
    //     address confirmer;
    //     bytes32 signatoryRecordHash;
    // }

    // //Stores the data required to index a given datastore's metadata
    // struct DataStoreSearchData {
    //     uint8 duration;
    //     uint256 timestamp;
    //     uint32 index;
    //     DataStoreMetadata metadata;
    // }

// TODO: NOTE THE DIFFERENCE IN VARIABLE ORDERING HERE, as opposed to `computeDataStoreHash`!!
        // broken into multiple steps to solve 'stack too deep'
        bytes memory calldataForStakeWithdrawalVerification = abi.encodePacked(
            searchData.metadata.headerHash,
            searchData.metadata.globalDataStoreId,
            searchData.metadata.durationDataStoreId,
            searchData.metadata.blockNumber,
            searchData.metadata.confirmer,
            searchData.metadata.fee,
            searchData.metadata.signatoryRecordHash
        );
        calldataForStakeWithdrawalVerification = abi.encodePacked(
            calldataForStakeWithdrawalVerification,
            searchData.duration,
            searchData.timestamp,
            searchData.index
        );
    // function stakeWithdrawalVerification(bytes calldata, uint256 initTimestamp, uint256 unlockTime) external view {
    //     bytes32 headerHash;
    //     uint32 globalDataStoreId; 
    //     uint32 durationDataStoreId;
    //     uint32 blockNumber; 
    //     address confirmer;
    //     uint96 fee;
    //     bytes32 signatoryRecordHash;

    //     uint8 duration; 
    //     uint256 initTime; 
    //     uint32 index;

    //     uint256 pointer = 132;
        
    //     assembly {
    //         headerHash := calldataload(pointer)
    //         globalDataStoreId := shr(224, calldataload(add(pointer, 32)))
    //         durationDataStoreId := shr(224, calldataload(add(pointer, 36)))
    //         blockNumber := shr(224, calldataload(add(pointer, 40)))
    //         confirmer := shr(96, calldataload(add(pointer, 44)))
    //         fee := shr(160, calldataload(add(pointer, 64)))
    //         signatoryRecordHash:= calldataload(add(pointer, 76))

    //         duration := shr(248, calldataload(add(pointer, 108)))
    //         initTime := calldataload(add(pointer, 109))
    //         index := shr(224, calldataload(add(pointer, 141)))
    //     }

    //     bytes32 dsHash = DataStoreHash.computeDataStoreHashFromArgs(headerHash, durationDataStoreId, globalDataStoreId, blockNumber, fee, confirmer, signatoryRecordHash);
    //     require(
    //         dataStoreHashesForDurationAtTimestamp[duration][initTime][index] == dsHash, "provided calldata does not match corresponding stored hash from (initDataStore)");

    //     //now we check if the dataStore is still active at the time
    //     //TODO: check if the duration is in days or seconds
    //     require(
    //         initTimestamp > initTime
    //              &&
    //             unlockTime <
    //             initTime + duration*86400,
    //         "task does not meet requirements"
    //     );

    // }





        cheats.startPrank(slasher.owner());
        address[] memory contractsToGiveSlashingPermission = new address[](1);
        contractsToGiveSlashingPermission[0] = address(dlsm);
        slasher.addPermissionedContracts(contractsToGiveSlashingPermission);
        cheats.stopPrank();

        // fraudproof the queued withdrawal

        // function fraudproofQueuedWithdrawal(
        //     IInvestmentStrategy[] calldata strategies,
        //     IERC20[] calldata tokens,
        //     uint256[] calldata shareAmounts,
        //     address depositor,
        //     WithdrawerAndNonce calldata withdrawerAndNonce,
        //     bytes calldata data,
        //     IServiceManager slashingContract
        // ) external {
        emit log("test is failing with next call");
        investmentManager.fraudproofQueuedWithdrawal(strategyArray, tokensArray, shareAmounts, sender, withdrawerAndNonce, calldataForStakeWithdrawalVerification, dlsm);
    }
    
    // deploys 'numStratsToAdd' strategies using '_testAddStrategy' and then deposits '1e18' to each of them from 'signers[0]'
    function testDepositStrategies(uint16 numStratsToAdd) public {
        _testDepositStrategies(signers[0], 1e18, numStratsToAdd);
    }

    //verifies that it is possible to deposit eigen
    function testDepositEigen(uint80 eigenToDeposit) public {
        // sanity check for inputs; keeps fuzzed tests from failing
        cheats.assume(eigenToDeposit < eigenTotalSupply / 2);
        _testDepositEigen(signers[0], eigenToDeposit);
    }

    function testDepositUnsupportedToken() public {
        IERC20 token = new ERC20PresetFixedSupply(
            "badToken",
            "BADTOKEN",
            100,
            address(this)
        );
        token.approve(address(investmentManager), type(uint256).max);
        cheats.expectRevert(bytes("InvestmentStrategyBase.deposit: Can only deposit underlyingToken"));
        investmentManager.depositIntoStrategy(msg.sender, strat, token, 10);
    }

    //ensure that investorStrats array updates correctly and only when appropriate
    function testInvestorStratUpdate() public {

    }

    function testSlashing() public {
        // hardcoded inputs
        address[2] memory accounts = [acct_0, acct_1];
        uint256[2] memory depositAmounts;
        uint256 amountToDeposit = 1e7;
        address _registrant = registrant;
        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        strategyArray[0] = strat;
        tokensArray[0] = weth;

        //register _registrant as an operator
        _testWethDeposit(_registrant, amountToDeposit);
        _testRegisterAsDelegate(_registrant, IDelegationTerms(_registrant));

        //make deposits in WETH strategy
        for (uint i=0; i<accounts.length; i++){            
            depositAmounts[i] = _testWethDeposit(accounts[i], amountToDeposit);
            _testDelegateToOperator(accounts[i], _registrant);

        }

        uint256[] memory shareAmounts = new uint256[](1);
        shareAmounts[0] = depositAmounts[0];

        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;

        //investmentManager.queueWithdrawal(strategyIndexes, strategyArray, tokensArray, shareAmounts, nonce);
        cheats.startPrank(address(slasher.delegation()));
        slasher.freezeOperator(_registrant);
        cheats.stopPrank();


        uint prev_shares = delegation.operatorShares(_registrant, strategyArray[0]);

        investmentManager.slashShares(
            _registrant, 
            acct_0, 
            strategyArray, 
            tokensArray, 
            strategyIndexes, 
            shareAmounts
        );

        require(delegation.operatorShares(_registrant, strategyArray[0]) + shareAmounts[0] == prev_shares, "Malicious Operator slashed by incorrect amount");
        
        //initiate withdrawal

        // InvestmentManagerStorage.WithdrawerAndNonce memory withdrawerAndNonce = InvestmentManagerStorage.WithdrawerAndNonce(accounts[0], 0);
        // uint96 queuedWithdrawalNonce = nonce.nonce;

        
    }
    
}
