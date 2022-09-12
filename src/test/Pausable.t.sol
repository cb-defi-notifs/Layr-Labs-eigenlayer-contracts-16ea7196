// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9.0;

import "./TestHelper.t.sol";

contract PausableTests is
    TestHelper
{
    ///@dev test that pausing a contract works
    function testPausability(
        uint256 amountToDeposit,
        uint256 amountToWithdraw
    ) public {
        cheats.assume(amountToDeposit <= weth.balanceOf(address(this)));
        cheats.assume(amountToWithdraw <= amountToDeposit);


        cheats.startPrank(pauser);
        investmentManager.pause();
        cheats.stopPrank();

        address sender = signers[0];
        uint256 strategyIndex = 0;
        _testDepositToStrategy(sender, amountToDeposit, weth, wethStrat);

        cheats.prank(sender);

        cheats.expectRevert(bytes("Pausable: paused"));
        investmentManager.withdrawFromStrategy(
                strategyIndex,
                wethStrat,
                weth,
                amountToWithdraw
        );
        
        cheats.stopPrank();
    }

    function testUnauthorizedPauser(
        address unauthorizedPauser
    ) public fuzzedAddress(unauthorizedPauser){
        cheats.startPrank(unauthorizedPauser);
        cheats.expectRevert(bytes("msg.sender is not permissioned as pauser"));
        investmentManager.pause();
        cheats.stopPrank();
    }

    function testSetPauser(address newPauser) fuzzedAddress(newPauser) public {
        cheats.startPrank(unpauser);
        pauserReg.setPauser(newPauser);
        cheats.stopPrank();

    }

    function testSetUnpauser(address newUnpauser) fuzzedAddress(newUnpauser) public {
        cheats.startPrank(unpauser);
        pauserReg.setUnpauser(newUnpauser);
        cheats.stopPrank();

    }

    function testSetPauserUnauthorized(
        address fakePauser, 
        address newPauser) 
        fuzzedAddress(newPauser) 
        fuzzedAddress(fakePauser)
    public {
        cheats.startPrank(fakePauser);
        cheats.expectRevert(bytes("msg.sender is not permissioned as unpauser"));
        pauserReg.setPauser(newPauser);
        cheats.stopPrank();
    }

}