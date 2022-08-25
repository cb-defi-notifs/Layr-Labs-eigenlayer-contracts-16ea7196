// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Deployer.t.sol";
import "../contracts/investment/InvestmentManagerStorage.sol";
import "./utils/DataStoreUtilsWrapper.sol";

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
        _testDepositToStrategy(sender, amountToDeposit, weth, wethStrat);
        uint256 strategyIndex = 0;
        _testWithdrawFromStrategy(sender, strategyIndex, amountToWithdraw, weth, wethStrat);
    }

    // verifies that a strategy gets removed from the dynamic array 'investorStrats' when the user no longer has any shares in the strategy
    function testRemovalOfStrategyOnWithdrawal(uint96 amountToDeposit) public {
        cheats.assume(amountToDeposit > 0);

        // hard-coded inputs
        IInvestmentStrategy _strat = wethStrat;
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

    function _createQueuedWithdrawal(
        address staker,
        bool registerAsDelegate,
        uint256 amountToDeposit,
        uint256 amountToWithdraw,
        IInvestmentStrategy[] memory strategyArray,
        IERC20[] memory tokensArray,
        uint256[] memory shareAmounts,
        uint256[] memory strategyIndexes,
        InvestmentManagerStorage.WithdrawerAndNonce memory withdrawerAndNonce
    )
        internal
    {
        require(amountToDeposit > amountToWithdraw, "_createQueuedWithdrawal: sanity check failed");

        // we do this here to ensure that `staker` is delegated if `registerAsDelegate` is true
        if (registerAsDelegate) {
            _testRegisterAsDelegate(staker, IDelegationTerms(staker));
            assertTrue(delegation.isDelegated(staker), "testQueuedWithdrawal: staker isn't delegated when they should be");
        }

        {
            //make deposit in WETH strategy
            uint256 amountDeposited = _testWethDeposit(staker, amountToDeposit);
            // We can't withdraw more than we deposit
            if (amountToWithdraw > amountDeposited) {
                cheats.expectRevert("InvestmentManager._removeShares: shareAmount too high");
            }
        }

        //queue the withdrawal
        cheats.startPrank(staker);
        investmentManager.queueWithdrawal(strategyIndexes, strategyArray, tokensArray, shareAmounts, withdrawerAndNonce);
        // If `staker` is actively delegated, check that `canCompleteQueuedWithdrawal` correct returns 'false', and
        if (delegation.isDelegated(staker)) {
            assertTrue(
                !investmentManager.canCompleteQueuedWithdrawal(strategyArray, tokensArray, shareAmounts, staker, withdrawerAndNonce),
                "testQueuedWithdrawal: user can immediately complete queued withdrawal (before waiting for fraudproof period), depsite being delegated"
            );
        }
        // If `staker` is *not* actively delegated, check that `canCompleteQueuedWithdrawal` correct returns 'ture', and         
        else if (delegation.isNotDelegated(staker)) {
            assertTrue(
                investmentManager.canCompleteQueuedWithdrawal(strategyArray, tokensArray, shareAmounts, staker, withdrawerAndNonce),
                "testQueuedWithdrawal: user *cannot* immediately complete queued withdrawal (before waiting for fraudproof period), despite *not* being delegated"
            );
        } else {
            revert("testQueuedWithdrawal: staker is somehow neither delegated nor *not* delegated, simultaneously");
        }
        cheats.stopPrank();
    }

    /**
     * Testing queued withdrawals in the investment manager
     * @notice This test registers `staker` as a delegate if `registerAsDelegate` is set to 'true', deposits `amountToDeposit` into a simple WETH strategy,
     *          and then starts a queued withdrawal for `amountToWithdraw` of shares in the same WETH strategy
     * @notice After initiating a queued withdrawal, this test checks that `investmentManager.canCompleteQueuedWithdrawal` immediately returns the correct
     *          response depending on whether `staker` is delegated or not. It then tries to call `completeQueuedWithdrawal` and verifies that it correctly
     *          (passes) reverts in the event that the `staker` is (not) delegated.
     */
    function testQueuedWithdrawal(
        address staker,
        bool registerAsDelegate,
        uint96 amountToDeposit,
        uint96 amountToWithdraw
    )
        public fuzzedAddress(staker)
    {
        cheats.assume(amountToDeposit > amountToWithdraw);
        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        uint256[] memory strategyIndexes = new uint256[](1);

        shareAmounts[0] = amountToWithdraw;
        // harcoded inputs
        {
            strategyArray[0] = wethStrat;
            tokensArray[0] = weth;
            strategyIndexes[0] = 0;
        }
        InvestmentManagerStorage.WithdrawerAndNonce memory withdrawerAndNonce = 
            InvestmentManagerStorage.WithdrawerAndNonce({
                withdrawer: staker,
                nonce: 0
            }
        );

        // create the queued withdrawal
        _createQueuedWithdrawal(staker, registerAsDelegate, amountToDeposit, amountToWithdraw, strategyArray, tokensArray, shareAmounts, strategyIndexes, withdrawerAndNonce);

        // If `staker` is actively delegated, then verify that the next call -- to `completeQueuedWithdrawal` -- reverts appropriately
        if (delegation.isDelegated(staker)) {
            cheats.expectRevert("InvestmentManager.completeQueuedWithdrawal: withdrawal waiting period has not yet passed and depositor is still delegated");
        }

        cheats.startPrank(staker);
        // try to complete the queued withdrawal
        investmentManager.completeQueuedWithdrawal(strategyArray, tokensArray, shareAmounts, staker, withdrawerAndNonce);
        // TODO: add checks surrounding successful completion (e.g. funds being correctly transferred)

        if (delegation.isDelegated(staker)) {
            // retrieve information about the queued withdrawal
            // bytes32 withdrawalRoot = investmentManager.calculateWithdrawalRoot(strategyArray, tokensArray, shareAmounts, withdrawerAndNonce);
            // (uint32 initTimestamp, uint32 unlockTimestamp, address withdrawer) = investmentManager.queuedWithdrawals(staker, withdrawalRoot);
            uint32 unlockTimestamp;
            {
                bytes32 withdrawalRoot = investmentManager.calculateWithdrawalRoot(strategyArray, tokensArray, shareAmounts, withdrawerAndNonce);
                (, unlockTimestamp, ) = investmentManager.queuedWithdrawals(staker, withdrawalRoot);                
            }
            // warp to unlock time (i.e. past fraudproof period) and verify that queued withdrawal works at this time
            cheats.warp(unlockTimestamp);
            investmentManager.completeQueuedWithdrawal(strategyArray, tokensArray, shareAmounts, staker, withdrawerAndNonce);
        }
        cheats.stopPrank();
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

        // harcoded inputs
        address staker = acct_0;
        bool registerAsDelegate = true;
        InvestmentManagerStorage.WithdrawerAndNonce memory withdrawerAndNonce = 
            InvestmentManagerStorage.WithdrawerAndNonce({
                withdrawer: staker,
                nonce: 0
            }
        );
        // TODO: this is copied input from `_testConfirmDataStoreSelfOperators` -- test fails unless I do this `warp`
        uint256 initTime = 1000000001;
        cheats.warp(initTime);
        {
            uint256 amountToDeposit = 10e7;
            uint256 amountToWithdraw = 1;
            strategyArray[0] = wethStrat;
            tokensArray[0] = weth;
            shareAmounts[0] = amountToWithdraw;
            strategyIndexes[0] = 0;
            // create the queued withdrawal
            _createQueuedWithdrawal(staker, registerAsDelegate, amountToDeposit, amountToWithdraw, strategyArray, tokensArray, shareAmounts, strategyIndexes, withdrawerAndNonce);
        }

        // retrieve information about the queued withdrawal
        // bytes32 withdrawalRoot = investmentManager.calculateWithdrawalRoot(strategyArray, tokensArray, shareAmounts, withdrawerAndNonce);
        // (uint32 initTimestamp, uint32 latestFraudproofTimestamp, address withdrawer) = investmentManager.queuedWithdrawals(sender, withdrawalRoot);

        IDataLayrServiceManager.DataStoreSearchData memory searchData;
        bytes32 signatoryRecordHash;
// BEGIN COPY PASTED CODE-BLOCK FROM `_testConfirmDataStoreSelfOperators`
{
        uint32 numberOfSigners = uint32(15);

        //register all the operators
        for (uint256 i = 0; i < numberOfSigners; ++i) {
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

        // ADDED CODE: fetch the signatoryRecordHash
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
        // END ADDED CODE

        dlsm.confirmDataStore(data, searchData);
        cheats.stopPrank();
}
// END COPY PASTED CODE-BLOCK FROM `_testConfirmDataStoreSelfOperators`

        // copy the signatoryRecordHash to the struct
        searchData.metadata.signatoryRecordHash = signatoryRecordHash;

        // deploy library-wrapper contract and use it to pack the searchData
        DataStoreUtilsWrapper dataStoreUtilsWrapper = new DataStoreUtilsWrapper();
        bytes memory calldataForStakeWithdrawalVerification = dataStoreUtilsWrapper.packDataStoreSearchDataExternal(searchData);

        // give slashing permission to the DLSM
        {
            cheats.startPrank(slasher.owner());
            address[] memory contractsToGiveSlashingPermission = new address[](1);
            contractsToGiveSlashingPermission[0] = address(dlsm);
            slasher.addPermissionedContracts(contractsToGiveSlashingPermission);
            cheats.stopPrank();
        }

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
        investmentManager.fraudproofQueuedWithdrawal(strategyArray, tokensArray, shareAmounts, staker, withdrawerAndNonce, calldataForStakeWithdrawalVerification, dlsm);
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
        investmentManager.depositIntoStrategy(msg.sender, wethStrat, token, 10);
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
        strategyArray[0] = wethStrat;
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
