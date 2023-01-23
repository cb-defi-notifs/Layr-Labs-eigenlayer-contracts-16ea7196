// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.12;

import "./EigenLayerTestHelper.t.sol";

contract PausableTests is EigenLayerTestHelper {
    ///@dev test that pausing a contract works
    function testPausingWithdrawalsFromInvestmentManager(uint256 amountToDeposit, uint256 amountToWithdraw) public {
        cheats.assume(amountToDeposit <= weth.balanceOf(address(this)));
        cheats.assume(amountToWithdraw <= amountToDeposit);

        address sender = getOperatorAddress(0);
        _testDepositToStrategy(sender, amountToDeposit, weth, wethStrat);

        cheats.startPrank(pauser);
        investmentManager.pause(type(uint256).max);
        cheats.stopPrank();

        // uint256 strategyIndex = 0;

        cheats.prank(sender);

        // TODO: write this to work with completing a queued withdrawal
        // cheats.expectRevert(bytes("Pausable: paused"));
        // investmentManager.withdrawFromStrategy(strategyIndex, wethStrat, weth, amountToWithdraw);
        // cheats.stopPrank();
    }

    function testUnauthorizedPauserInvestmentManager(address unauthorizedPauser)
        public
        fuzzedAddress(unauthorizedPauser)
    {
        cheats.assume(unauthorizedPauser != eigenLayerPauserReg.pauser());
        cheats.startPrank(unauthorizedPauser);
        cheats.expectRevert(bytes("msg.sender is not permissioned as pauser"));
        investmentManager.pause(type(uint256).max);
        cheats.stopPrank();
    }

    function testSetPauser(address newPauser) public fuzzedAddress(newPauser) {
        cheats.startPrank(unpauser);
        eigenLayerPauserReg.setPauser(newPauser);
        cheats.stopPrank();
    }

    function testSetUnpauser(address newUnpauser) public fuzzedAddress(newUnpauser) {
        cheats.startPrank(unpauser);
        eigenLayerPauserReg.setUnpauser(newUnpauser);
        cheats.stopPrank();
    }

    function testSetPauserUnauthorized(address fakePauser, address newPauser)
        public
        fuzzedAddress(newPauser)
        fuzzedAddress(fakePauser)
    {
        cheats.assume(fakePauser != eigenLayerPauserReg.unpauser());
        cheats.startPrank(fakePauser);
        cheats.expectRevert(bytes("msg.sender is not permissioned as unpauser"));
        eigenLayerPauserReg.setPauser(newPauser);
        cheats.stopPrank();
    }
}
