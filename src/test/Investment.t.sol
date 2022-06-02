// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Deployer.t.sol";
import "../contracts/investment/InvestmentManagerStorage.sol";


contract InvestmentTests is
    EigenLayrDeployer
{
    IInvestmentStrategy[] strategy_arr;
    IERC20[] tokens;

    //verifies that depositing WETH works
    function testWethDeposit(uint256 amountToDeposit)
        public
        returns (uint256 amountDeposited)
    {
        return _testWethDeposit(signers[0], amountToDeposit);
    }

    //checks that it is possible to withdraw WETH
    function testWethWithdrawal(
        uint256 amountToDeposit,
        uint256 amountToWithdraw
    ) public {
        _testWethWithdrawal(signers[0], amountToDeposit, amountToWithdraw);
    }

    //testing queued withdrawals in the investment manager
    function testQueuedWithdrawal(
        uint256 amountToDeposit,
        uint256 amountToWithdraw 
    ) public {
        //initiate deposits
        address[2] memory accounts = [acct_0, acct_1];
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


// Coverage for EigenLayrDeposit contract //
    // TODOs:
    // testDepositPOSProof

    //Testing deposits in Eigen Layr Contracts - check msg.value
    function testDepositETHIntoConsensusLayer()
        public
        returns (uint256 amountDeposited)
    {
        amountDeposited = _testDepositETHIntoConsensusLayer(
            signers[0],
            amountDeposited
        );
    }

    // tests that it is possible to deposit ETH into liquid staking through the 'deposit' contract
    // also verifies that the subsequent strategy shares are credited correctly
    function testDepositETHIntoLiquidStaking()
        public
        returns (uint256 amountDeposited)
    {
        return
            _testDepositETHIntoLiquidStaking(
                signers[0],
                1e18,
                liquidStakingMockToken,
                liquidStakingMockStrat
            );
    }

    //checks that it is possible to prove a consensus layer deposit
    function testCleProof() public {
        address depositor = address(0x1234123412341234123412341234123412341235);
        uint256 amount = 100;
        bytes32[] memory proof = new bytes32[](3);
        proof[0] = bytes32(
            0x0c70933f97e33ce23514f82854b7000db6f226a3c6dd2cf42894ce71c9bb9e8b
        );
        proof[1] = bytes32(
            0x200634f4269b301e098769ce7fd466ca8259daad3965b977c69ca5e2330796e1
        );
        proof[2] = bytes32(
            0x1944162db3ee014776b5da7dbb53c9d7b9b11b620267f3ea64a7f46a5edb403b
        );
        cheats.prank(depositor);
        deposit.proveLegacyConsensusLayerDeposit(
            proof,
            address(0),
            "0x",
            amount
        );
        //make sure their proofOfStakingEth has updated
        assertEq(investmentManager.getProofOfStakingEth(depositor), amount);
    }

    //checks that an incorrect proof for a consensus layer deposit reverts properly
    function testConfirmRevertIncorrectCleProof() public {
        address depositor = address(0x1234123412341234123412341234123412341235);
        uint256 amount = 1000;
        bytes32[] memory proof = new bytes32[](3);
        proof[0] = bytes32(
            0x0c70933f97e33ce23514f82854b7000db6f226a3c6dd2cf42894ce71c9bb9e8b
        );
        proof[1] = bytes32(
            0x200634f4269b301e098769ce7fd466ca8259daad3965b977c69ca5e2330796e1
        );
        proof[2] = bytes32(
            0x1944162db3ee014776b5da7dbb53c9d7b9b11b620267f3ea64a7f46a5edb403b
        );
        cheats.prank(depositor);
        cheats.expectRevert("Invalid merkle proof");
        deposit.proveLegacyConsensusLayerDeposit(
            proof,
            address(0),
            "0x",
            amount
        );
    }

    
}
