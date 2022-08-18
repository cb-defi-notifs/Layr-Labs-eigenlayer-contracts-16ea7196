// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Deployer.t.sol";
import "../contracts/investment/InvestmentManagerStorage.sol";


contract InvestmentStrategyTests is
    EigenLayrDeployer 
{



    /// @notice This function tests to ensure that a delegation contract
    ///         cannot be intitialized multiple times
    function testCannotInitMultipleTimesDelegation() public {
        //delegation has already been initialized in the Deployer test contract
        cheats.expectRevert(
            bytes("Initializable: contract is already initialized")
        );
        strat.initialize(
            address(investmentManager), 
            weth
        );
    }

    ///@notice This function tests to ensure that only the investmentManager
    ///         can deposit into a strategy
    ///@param invalidDepositor is the non-registered
    function testInvalidCalltoDeposit(address invalidDepositor) public {
        cheats.assume(invalidDepositor != address(0));
        cheats.startPrank(invalidDepositor);

        cheats.expectRevert(bytes("only the InvestmentManager can call this function"));
        strat.deposit(weth, 1e18);

        cheats.stopPrank();



    }










    }