// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "./TestHelper.t.sol";
import "../contracts/investment/InvestmentManagerStorage.sol";
import "./utils/DataStoreUtilsWrapper.sol";

contract InvestmentTests is TestHelper {
    /**
     * @notice Verifies that it is possible to deposit WETH
     * @param amountToDeposit Fuzzed input for amount of WETH to deposit
     */
    function testWethDeposit(uint256 amountToDeposit) public returns (uint256 amountDeposited) {
        return _testWethDeposit(signers[0], amountToDeposit);
    }

    ///@notice This test verifies that it is possible to withdraw WETH after depositing it
    ///@param amountToDeposit The amount of WETH to try depositing
    ///@param amountToWithdraw The amount of shares to try withdrawing
    function testWethWithdrawal(uint96 amountToDeposit, uint96 amountToWithdraw) public {
        // want to deposit at least 1 wei
        cheats.assume(amountToDeposit > 0);
        // want to withdraw at least 1 wei
        cheats.assume(amountToWithdraw > 0);
        // cannot withdraw more than we deposit
        cheats.assume(amountToWithdraw <= amountToDeposit);
        // hard-coded inputs
        address sender = signers[0];
        uint256 strategyIndex = 0;
        _testDepositToStrategy(sender, amountToDeposit, weth, wethStrat);
        _testWithdrawFromStrategy(sender, strategyIndex, amountToWithdraw, weth, wethStrat);
    }

    /**
     * @notice Verifies that a strategy gets removed from the dynamic array 'investorStrats' when the user no longer has any shares in the strategy
     * @param amountToDeposit Fuzzed input for the amount deposited into the strategy, prior to withdrawing all shares
     */
    function testRemovalOfStrategyOnWithdrawal(uint96 amountToDeposit) public {
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
        assertEq(
            investorStratsLengthBefore - investorStratsLengthAfter,
            1,
            "testRemovalOfStrategyOnWithdrawal: strategy not removed from dynamic array when it should be"
        );
    }

    /**
     * Testing queued withdrawals in the investment manager
     * @notice This test registers `staker` as a delegate if `registerAsDelegate` is set to 'true', deposits `amountToDeposit` into a simple WETH strategy,
     * and then starts a queued withdrawal for `amountToWithdraw` of shares in the same WETH strategy. It then tries to call `completeQueuedWithdrawal`
     * and verifies that it correctly (passes) reverts in the event that the `staker` is (not) delegated.
     * @notice In the event that the call to `completeQueuedWithdrawal` correctly reverted above, this function then fast-forwards to just past the `unlockTime`
     * for the queued withdrawal and verifies that a call to `completeQueuedWithdrawal` completes appropriately.
     * @param staker The caller who will create the queued withdrawal.
     * @param registerAsOperator When true, `staker` will register as a delegate inside of the call to `_createQueuedWithdrawal`. Otherwise they will not.
     * @param amountToDeposit Fuzzed input of amount of WETH deposited. Currently `_createQueuedWithdrawal` uses this as an input to `_testWethDeposit`.
     * @param amountToWithdraw Fuzzed input of the amount of shares to queue the withdrawal for.
     */
    function testQueuedWithdrawal(
        address staker,
        bool registerAsOperator,
        uint96 amountToDeposit,
        uint96 amountToWithdraw
    )
        public
        fuzzedAddress(staker)
    {
        // want to deposit at least 1 wei
        cheats.assume(amountToDeposit > 0);
        // want to withdraw at least 1 wei
        cheats.assume(amountToWithdraw > 0);
        // cannot withdraw more than we deposit
        cheats.assume(amountToWithdraw <= amountToDeposit);

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
        IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce =
            IInvestmentManager.WithdrawerAndNonce({withdrawer: staker, nonce: 0});

        // create the queued withdrawal
        _createQueuedWithdrawal(staker, registerAsOperator, amountToDeposit, strategyArray, tokensArray, shareAmounts, strategyIndexes, withdrawerAndNonce);

        // If `staker` is actively delegated, then verify that the next call -- to `completeQueuedWithdrawal` -- reverts appropriately
        if (delegation.isDelegated(staker)) {
            cheats.expectRevert(
                "InvestmentManager.completeQueuedWithdrawal: withdrawal waiting period has not yet passed and depositor is still delegated"
            );
        }

        cheats.startPrank(staker);
        // try to complete the queued withdrawal
        investmentManager.completeQueuedWithdrawal(strategyArray, tokensArray, shareAmounts, staker, withdrawerAndNonce, true);
        // TODO: add checks surrounding successful completion (e.g. funds being correctly transferred)

        if (delegation.isDelegated(staker)) {
            // retrieve information about the queued withdrawal
            // bytes32 withdrawalRoot = investmentManager.calculateWithdrawalRoot(strategyArray, tokensArray, shareAmounts, withdrawerAndNonce);
            // (uint32 initTimestamp, uint32 unlockTimestamp, address withdrawer) = investmentManager.queuedWithdrawals(staker, withdrawalRoot);
            uint32 unlockTimestamp;
            {
                bytes32 withdrawalRoot = investmentManager.calculateWithdrawalRoot(
                    strategyArray, tokensArray, shareAmounts, withdrawerAndNonce
                );
                (, unlockTimestamp,) = investmentManager.queuedWithdrawals(staker, withdrawalRoot);
            }
            // warp to unlock time (i.e. past fraudproof period) and verify that queued withdrawal works at this time
            cheats.warp(unlockTimestamp);
            investmentManager.completeQueuedWithdrawal(strategyArray, tokensArray, shareAmounts, staker, withdrawerAndNonce, true);
        }
        cheats.stopPrank();
    }

    /**
     * @notice This test checks that fraudproofing queued withdrawals through the InvestmentManager is possible.
     * @param amountToDeposit Fuzzed input of amount of WETH deposited. Currently `_createQueuedWithdrawal` uses this as an input to `_testWethDeposit`.
     * @param amountToWithdraw Fuzzed input of the amount of shares to queue the withdrawal for.
     */
    function testFraudproofQueuedWithdrawal(uint96 amountToDeposit, uint96 amountToWithdraw) public {
        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        uint256[] memory strategyIndexes = new uint256[](1);

        // want to deposit at least 1 wei
        cheats.assume(amountToDeposit > 0);
        // want to withdraw at least 1 wei
        cheats.assume(amountToWithdraw > 0);
        // cannot withdraw more than we deposit
        cheats.assume(amountToWithdraw <= amountToDeposit);

        // harcoded inputs
        address staker = acct_0;
        bool registerAsOperator = true;
        IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce = 
            IInvestmentManager.WithdrawerAndNonce({
                withdrawer: staker,
                nonce: 0
            }
        );
        // TODO: this is copied input from `_testConfirmDataStoreSelfOperators` -- test fails unless I do this `warp`
        uint256 initTime = 1000000001;
        cheats.warp(initTime);
        {
            // harcoded inputs, also somewhat shared with `_createQueuedWithdrawal`
            strategyArray[0] = wethStrat;
            tokensArray[0] = weth;
            shareAmounts[0] = amountToWithdraw;
            strategyIndexes[0] = 0;
            // create the queued withdrawal
            bytes32 withdrawalRoot = _createQueuedWithdrawal(staker, registerAsOperator, amountToDeposit, strategyArray, tokensArray, shareAmounts, strategyIndexes, withdrawerAndNonce);
            cheats.prank(staker);
            investmentManager.startQueuedWithdrawalWaitingPeriod(
                staker,
                withdrawalRoot,
                uint32(block.timestamp)
            );
        }

        // retrieve information about the queued withdrawal
        // bytes32 withdrawalRoot = investmentManager.calculateWithdrawalRoot(strategyArray, tokensArray, shareAmounts, withdrawerAndNonce);
        // (uint32 initTimestamp, uint32 latestFraudproofTimestamp, address withdrawer) = investmentManager.queuedWithdrawals(sender, withdrawalRoot);

        // confirm a data store and get the `searchData` for "finding" it
        uint8 numberOfSigners = uint8(15);
        IDataLayrServiceManager.DataStoreSearchData memory searchData;
        (, searchData) = _testConfirmDataStoreSelfOperators(numberOfSigners);

        // deploy library-wrapper contract and use it to pack the searchData
        DataStoreUtilsWrapper dataStoreUtilsWrapper = new DataStoreUtilsWrapper();
        bytes memory calldataForStakeWithdrawalVerification =
            dataStoreUtilsWrapper.packDataStoreSearchDataExternal(searchData);

        // give slashing permission to the DLSM
        {
            cheats.startPrank(slasher.owner());
            address[] memory contractsToGiveSlashingPermission = new address[](1);
            contractsToGiveSlashingPermission[0] = address(dlsm);
            slasher.addGloballyPermissionedContracts(contractsToGiveSlashingPermission);
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
        investmentManager.challengeQueuedWithdrawal(strategyArray, tokensArray, shareAmounts, staker, withdrawerAndNonce, calldataForStakeWithdrawalVerification, dlsm);
    }

    /// @notice deploys 'numStratsToAdd' strategies using '_testAddStrategy' and then deposits '1e18' to each of them from 'signers[0]'
    /// @param numStratsToAdd is the number of strategies being added and deposited into
    function testDepositStrategies(uint16 numStratsToAdd) public {
        _testDepositStrategies(signers[0], 1e18, numStratsToAdd);
    }

    /// @notice Verifies that it is possible to deposit eigen.
    /// @param eigenToDeposit is amount of eigen to deposit into the eigen strategy
    function testDepositEigen(uint96 eigenToDeposit) public {
        // sanity check for inputs; keeps fuzzed tests from failing
        cheats.assume(eigenToDeposit < eigenTotalSupply);
        _testDepositEigen(signers[0], eigenToDeposit);
    }

    /**
     * @notice Tries to deposit an unsupported token into an `InvestmentStrategyBase` contract by calling `investmentManager.depositIntoStrategy`.
     * Verifies that reversion occurs correctly.
     */
    function testDepositUnsupportedToken() public {
        IERC20 token = new ERC20PresetFixedSupply(
            "badToken",
            "BADTOKEN",
            100,
            address(this)
        );
        token.approve(address(investmentManager), type(uint256).max);
        cheats.expectRevert(bytes("InvestmentStrategyBase.deposit: Can only deposit underlyingToken"));
        investmentManager.depositIntoStrategy(wethStrat, token, 10);
    }

    /**
     * @notice Tries to deposit into an unsupported strategy by calling `investmentManager.depositIntoStrategy`.
     * Verifies that reversion occurs correctly.
     */
    function testDepositNonexistantStrategy(address nonexistentStrategy) public fuzzedAddress(nonexistentStrategy) {
        // assume that the fuzzed address is not already a contract!
        uint256 size;
        assembly {
            size := extcodesize(nonexistentStrategy)
        }
        cheats.assume(size == 0);
        // check against calls from precompile addresses -- was getting fuzzy failures from this
        cheats.assume(uint160(nonexistentStrategy) > 9);
        
        // harcoded input
        uint256 testDepositAmount = 10;

        IERC20 token = new ERC20PresetFixedSupply(
            "badToken",
            "BADTOKEN",
            100,
            address(this)
        );
        token.approve(address(investmentManager), type(uint256).max);
        cheats.expectRevert();
        investmentManager.depositIntoStrategy(IInvestmentStrategy(nonexistentStrategy), token, testDepositAmount);
    }

    /**
     * @notice Creates a queued withdrawal from `staker`. Begins by registering the staker as a delegate (if specified), then deposits `amountToDeposit`
     * into the WETH strategy, and then queues a withdrawal using
     * `investmentManager.queueWithdrawal(strategyIndexes, strategyArray, tokensArray, shareAmounts, withdrawerAndNonce)`
     * @notice After initiating a queued withdrawal, this test checks that `investmentManager.canCompleteQueuedWithdrawal` immediately returns the correct
     * response depending on whether `staker` is delegated or not.
     * @param staker The address to initiate the queued withdrawal
     * @param registerAsOperator If true, `staker` will also register as a delegate in the course of this function
     * @param amountToDeposit The amount of WETH to deposit
     */
    function _createQueuedWithdrawal(
        address staker,
        bool registerAsOperator,
        uint256 amountToDeposit,
        IInvestmentStrategy[] memory strategyArray,
        IERC20[] memory tokensArray,
        uint256[] memory shareAmounts,
        uint256[] memory strategyIndexes,
        IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce
    )
        internal returns(bytes32)
    {
        require(amountToDeposit >= shareAmounts[0], "_createQueuedWithdrawal: sanity check failed");

        // we do this here to ensure that `staker` is delegated if `registerAsOperator` is true
        if (registerAsOperator) {
            assertTrue(!delegation.isDelegated(staker), "testQueuedWithdrawal: staker is already delegated");
            _testRegisterAsOperator(staker, IDelegationTerms(staker));
            assertTrue(delegation.isDelegated(staker), "testQueuedWithdrawal: staker isn't delegated when they should be");
        }

        {
            //make deposit in WETH strategy
            uint256 amountDeposited = _testWethDeposit(staker, amountToDeposit);
            // We can't withdraw more than we deposit
            if (shareAmounts[0] > amountDeposited) {
                cheats.expectRevert("InvestmentManager._removeShares: shareAmount too high");
            }
        }

        //queue the withdrawal
        cheats.startPrank(staker);
        bytes32 withdrawalRoot = investmentManager.queueWithdrawal(strategyIndexes, strategyArray, tokensArray, shareAmounts, withdrawerAndNonce);
        // If `staker` is actively delegated, check that `canCompleteQueuedWithdrawal` correct returns 'false', and
        if (delegation.isDelegated(staker)) {
            assertTrue(
                !investmentManager.canCompleteQueuedWithdrawal(strategyArray, tokensArray, shareAmounts, staker, withdrawerAndNonce),
                "_createQueuedWithdrawal: user can immediately complete queued withdrawal (before waiting for fraudproof period), depsite being delegated"
            );
        }
        // If `staker` is *not* actively delegated, check that `canCompleteQueuedWithdrawal` correct returns 'ture', and
        else if (delegation.isNotDelegated(staker)) {
            assertTrue(
                investmentManager.canCompleteQueuedWithdrawal(strategyArray, tokensArray, shareAmounts, staker, withdrawerAndNonce),
                "_createQueuedWithdrawal: user *cannot* immediately complete queued withdrawal (before waiting for fraudproof period), despite *not* being delegated"
            );
        } else {
            revert("_createQueuedWithdrawal: staker is somehow neither delegated nor *not* delegated, simultaneously");
        }
        cheats.stopPrank();
        return withdrawalRoot;
    }

    // TODO: add test(s) that confirm deposits + withdrawals *of zero shares* fail correctly.
}
