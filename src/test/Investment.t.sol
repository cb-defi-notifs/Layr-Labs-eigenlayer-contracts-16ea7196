// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Deployer.t.sol";
import "../contracts/investment/InvestmentManagerStorage.sol";


contract InvestmentTests is
    EigenLayrDeployer
{
    IInvestmentStrategy[] strategy_arr;
    IERC20[] tokens;

    /**
     * @notice Verifies that it is possible to deposit WETH
     * 
     */
    function testWethDeposit(uint256 amountToDeposit)
        public
        returns (uint256 amountDeposited)
    {
        return _testWethDeposit(signers[0], amountToDeposit);
    }

    function testWethDepositWithEmit() public {
        emit log_named_uint("testWethDeposit(1e7)",testWethDeposit(1e7));
    }

    /**
     * @notice Verifies that it is possible to withdraw WETH
     * 
     */
    function testWethWithdrawal(
        uint96 amountToDeposit,
        uint96 amountToWithdraw
    ) public {
        cheats.assume(amountToDeposit > 0);
        cheats.assume(amountToWithdraw > 0);
        _testWethWithdrawal(signers[0], amountToDeposit, amountToWithdraw);
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
        uint256 amountToDeposit
        // ,uint256 amountToWithdraw 
    ) public {
        //initiate deposits
        address[2] memory  accounts = [acct_0, acct_1];
        uint256[2] memory depositAmounts;


        amountToDeposit = 10e7;

        //make deposits in WETH strategy
        for (uint i=0; i<accounts.length; i++){
            cheats.deal(accounts[i], amountToDeposit);
            depositAmounts[i] = _testWethDeposit(accounts[i], amountToDeposit);

        }
        strategy_arr.push(strat);
        tokens.push(weth);
        
        //queue the withdrawal
        for (uint i=0; i<accounts.length; i++){ 
            cheats.startPrank(accounts[i]);

            uint256[] memory shareAmounts = new uint256[](1);
            shareAmounts[0] = depositAmounts[i];

            uint256[] memory strategyIndexes = new uint256[](1);
            strategyIndexes[0] = 0;

            InvestmentManagerStorage.WithdrawerAndNonce memory nonce = InvestmentManagerStorage.WithdrawerAndNonce(accounts[i], 0);
            investmentManager.queueWithdrawal(strategyIndexes, strategy_arr, tokens, shareAmounts, nonce);
            investmentManager.canCompleteQueuedWithdrawal(strategy_arr, tokens, shareAmounts, accounts[i], nonce.nonce);
            investmentManager.completeQueuedWithdrawal(strategy_arr, tokens, shareAmounts, accounts[i], nonce.nonce);
            cheats.stopPrank();
        }
    }

    //testing queued withdrawals in the investment manager
    function _testFraudProofQueuedWithdrawal(
        uint256 amountToDeposit
        // ,uint256 amountToWithdraw 
    ) public {
        strategy_arr.push(strat);
        tokens.push(weth);

        uint256[] memory shareAmounts = new uint256[](1);
        cheats.deal(acct_0, amountToDeposit);


        _testWethDeposit(acct_0, amountToDeposit);


        


        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;

        //init and commit DataStore
        bytes memory data = _testConfirmDataStoreSelfOperators(15);
        
        //queue the withdrawal        
        cheats.startPrank(acct_0);



        InvestmentManagerStorage.WithdrawerAndNonce memory nonce = InvestmentManagerStorage.WithdrawerAndNonce(acct_0, 0);
        investmentManager.queueWithdrawal(strategyIndexes, strategy_arr, tokens, shareAmounts, nonce);

        investmentManager.fraudproofQueuedWithdrawal(strategy_arr, tokens, shareAmounts, acct_0, nonce.nonce, data, dlsm);


        cheats.stopPrank();

        
        
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
    

    // TODO: FIX THIS!
    /*
    //verifies that it is possible to deposit eigen and then withdraw it
    function testDepositAndWithdrawEigen(uint80 eigenToDeposit, uint256 amountToWithdraw) public {
        // sanity check for inputs; keeps fuzzed tests from failing
        cheats.assume(eigenToDeposit < eigenTotalSupply / 2);
        cheats.assume(amountToWithdraw <= eigenToDeposit);
        _testDepositEigen(signers[0], eigenToDeposit);
        uint256 eigenBeforeWithdrawal = eigen.balanceOf(signers[0], eigenTokenId);

        cheats.startPrank(signers[0]);
        investmentManager.withdrawEigen(amountToWithdraw);
        cheats.stopPrank();

        uint256 eigenAfterWithdrawal = eigen.balanceOf(signers[0], eigenTokenId);
        assertEq(eigenAfterWithdrawal - eigenBeforeWithdrawal, amountToWithdraw, "incorrect eigen sent on withdrawal");
    }
    */

    // Coverage for EigenLayrDeposit contract //
    // TODOs:
    // testDepositPOSProof

    function testSlashing(uint256 amountToDeposit) public{

        address[2] memory accounts = [acct_0, acct_1];
        uint256[2] memory depositAmounts;


        amountToDeposit = 1e7;

        //register registrant as an operator
        cheats.deal(registrant, amountToDeposit);
        _testWethDeposit(registrant, amountToDeposit);
        _testRegisterAsDelegate(registrant, IDelegationTerms(registrant));

        //make deposits in WETH strategy
        for (uint i=0; i<accounts.length; i++){
            
            cheats.deal(accounts[i], amountToDeposit);
            depositAmounts[i] = _testWethDeposit(accounts[i], amountToDeposit);
            _testDelegateToOperator(accounts[i], registrant);

        }
        strategy_arr.push(strat);
        tokens.push(weth);

        uint256[] memory shareAmounts = new uint256[](1);
        shareAmounts[0] = depositAmounts[0];

        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;

        //investmentManager.queueWithdrawal(strategyIndexes, strategy_arr, tokens, shareAmounts, nonce);
        cheats.startPrank(address(slasher.delegation()));
        slasher.freezeOperator(registrant);
        cheats.stopPrank();


        uint prev_shares = delegation.operatorShares(registrant, strategy_arr[0]);

        investmentManager.slashShares(
            registrant, 
            acct_0, 
            strategy_arr, 
            tokens, 
            strategyIndexes, 
            shareAmounts
        );

        require(delegation.operatorShares(registrant, strategy_arr[0]) + shareAmounts[0] == prev_shares, "Malicious Operator slashed by incorrect amount");
        
        //initiate withdrawal

        // InvestmentManagerStorage.WithdrawerAndNonce memory withdrawerAndNonce = InvestmentManagerStorage.WithdrawerAndNonce(accounts[0], 0);
        // uint96 queuedWithdrawalNonce = nonce.nonce;

        
    }
    
}
