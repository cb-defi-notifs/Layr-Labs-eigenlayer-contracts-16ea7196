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
            weth
        );
    }

    ///@notice This function tests to ensure that only the investmentManager
    ///         can deposit into a strategy
    ///@param invalidDepositor is the non-registered depositor
    function testInvalidCalltoDeposit(address invalidDepositor) public {
        IERC20 underlyingToken = strat.underlyingToken();
        cheats.assume(invalidDepositor != address(0));
        cheats.startPrank(invalidDepositor);

        cheats.expectRevert(bytes("InvestmentStrategyBase.onlyInvestmentManager"));
        strat.deposit(underlyingToken, 1e18);

        cheats.stopPrank();
    }

    ///@notice This function tests to ensure that only the investmentManager
    ///         can deposit into a strategy
    ///@param invalidWithdrawer is the non-registered withdrawer
    ///@param depositor is the depositor for which the shares are being withdrawn
    function testInvalidCalltoWithdraw(address depositor, address invalidWithdrawer) public {
        IERC20 underlyingToken = strat.underlyingToken();
        cheats.assume(invalidWithdrawer != address(0));
        cheats.startPrank(invalidWithdrawer);

        cheats.expectRevert(bytes("InvestmentStrategyBase.onlyInvestmentManager"));
        strat.withdraw(depositor, underlyingToken, 1e18);

        cheats.stopPrank();
    }

    ///@notice This function tests ensures that withdrawing for a depositor that never
    ///         actually deposited fails.
    ///@param depositor is the depositor for which the shares are being withdrawn
    function testInvalidWithdrawal(address depositor) public {
        IERC20 underlyingToken = strat.underlyingToken();
        cheats.assume(depositor != address(0));
        cheats.startPrank(address(investmentManager));

        cheats.expectRevert(bytes("InvestmentStrategyBase.withdraw: shareAmount must be less than or equal to totalShares"));
        strat.withdraw(depositor, underlyingToken, 1e18);

        cheats.stopPrank();
    }












    }