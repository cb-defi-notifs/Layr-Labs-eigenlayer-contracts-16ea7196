// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Deployer.t.sol";

contract InvestmentTests is
    EigenLayrDeployer
{
    //verifies that depositing WETH works
    function testWethDeposit(uint256 amountToDeposit)
        public
        returns (uint256 amountDeposited)
    {
        return _testWethDeposit(signers[0], amountToDeposit);
    }

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

    //checks that it is possible to withdraw WETH
    function testWethWithdrawal(
        uint256 amountToDeposit,
        uint256 amountToWithdraw
    ) public {
        _testWethWithdrawal(signers[0], amountToDeposit, amountToWithdraw);
    }

    function testAddStrategies(uint16 numStratsToAdd) public {
        cheats.assume(numStratsToAdd > 0 && numStratsToAdd <= 20);
        _testAddStrategies(numStratsToAdd);
    }
    
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

    // TODOs:
    // testDepositEthIntoConsensusLayer
    // testDepositPOSProof

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
