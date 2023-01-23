// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "./EigenLayerDeployer.t.sol";
import "./EigenLayerTestHelper.t.sol";

contract SlasherTests is EigenLayerTestHelper {
    /**
     * @notice this function tests the slashing process by first freezing
     * the operator and then calling the investmentManager.slashShares()
     * to actually enforce the slashing conditions.
     */
    function testSlashing() public {
        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);

        // hardcoded inputs
        address[2] memory accounts = [acct_0, acct_1];
        uint256[2] memory depositAmounts;
        uint256 amountToDeposit = 1e7;
        address _operator = operator;
        strategyArray[0] = wethStrat;
        tokensArray[0] = weth;

        // have `_operator` make deposits in WETH strategy
        _testDepositWeth(_operator, amountToDeposit);
        // register `_operator` as an operator
        _testRegisterAsOperator(_operator, IDelegationTerms(_operator));

        // make deposit in WETH strategy from each of `accounts`, then delegate them to `_operator`
        for (uint256 i = 0; i < accounts.length; i++) {
            depositAmounts[i] = _testDepositWeth(accounts[i], amountToDeposit);
            _testDelegateToOperator(accounts[i], _operator);
        }

        uint256[] memory shareAmounts = new uint256[](1);
        shareAmounts[0] = depositAmounts[0];

        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;

        cheats.startPrank(_operator);
        slasher.optIntoSlashing(address(this));
        cheats.stopPrank();

        slasher.freezeOperator(_operator);

        uint256 prev_shares = delegation.operatorShares(_operator, strategyArray[0]);

        investmentManager.slashShares(_operator, acct_0, strategyArray, tokensArray, strategyIndexes, shareAmounts);

        require(
            delegation.operatorShares(_operator, strategyArray[0]) + shareAmounts[0] == prev_shares,
            "Malicious Operator slashed by incorrect amount"
        );
    }

    /**
     * @notice testing ownable permissions for slashing functions
     * addPermissionedContracts(), removePermissionedContracts()
     * and resetFrozenStatus().
     */
    function testOnlyOwnerFunctions(address incorrectCaller, address inputAddr)
        public
        fuzzedAddress(incorrectCaller)
        fuzzedAddress(inputAddr)
    {
        cheats.assume(incorrectCaller != slasher.owner());
        cheats.startPrank(incorrectCaller);
        address[] memory addressArray = new address[](1);
        addressArray[0] = inputAddr;
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        slasher.resetFrozenStatus(addressArray);
        cheats.stopPrank();
    }
}
