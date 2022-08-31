// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Deployer.t.sol";

contract SlasherTests is
    EigenLayrDeployer
{
    function testSlashing() public {
        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);

        // hardcoded inputs
        address[2] memory accounts = [acct_0, acct_1];
        uint256[2] memory depositAmounts;
        uint256 amountToDeposit = 1e7;
        address _registrant = registrant;
        strategyArray[0] = wethStrat;
        tokensArray[0] = weth;

        // have `_registrant` make deposits in WETH strategy
        _testWethDeposit(_registrant, amountToDeposit);
        // register `_registrant` as an operator
        _testRegisterAsDelegate(_registrant, IDelegationTerms(_registrant));

        // make deposit in WETH strategy from each of `accounts`, then delegate them to `_registrant`
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
    }

    function testOnlyOwnerFunctions(address incorrectCaller, address inputAddr)
        public fuzzedAddress(incorrectCaller) fuzzedAddress(inputAddr)
    {
        cheats.assume(incorrectCaller != slasher.owner());
        cheats.startPrank(incorrectCaller);
        address[] memory addressArray = new address[](1);
        addressArray[0] = inputAddr;
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        slasher.addPermissionedContracts(addressArray);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        slasher.removePermissionedContracts(addressArray);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        slasher.resetFrozenStatus(addressArray);
        cheats.stopPrank();
    }
    
}
