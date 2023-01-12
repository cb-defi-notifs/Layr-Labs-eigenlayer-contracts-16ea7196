// //SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";

import "../../contracts/core/InvestmentManager.sol";
import "../mocks/DelegationMock.sol";
import "../mocks/SlasherMock.sol";
import "../EigenLayrTestHelper.t.sol";


contract UnitTests is EigenLayrTestHelper {

    InvestmentManager investmentManagerMock;
    DelegationMock delegationMock;
    SlasherMock slasherMock;

    uint256 GWEI_TO_WEI = 1e9;

    function setUp() override virtual public{
        EigenLayrDeployer.setUp();

        investmentManagerMock = new InvestmentManager(delegationMock, eigenPodManager, slasherMock);
        slasherMock = new SlasherMock();
        delegationMock = new DelegationMock();
        IERC20 dummyToken = new ERC20PresetFixedSupply(
            "dummy",
            "DUMMY",
            REQUIRED_BALANCE_WEI,
            address(investmentManagerMock)
        );

        
        InvestmentStrategyBase dummyStrat = new InvestmentStrategyBase(investmentManagerMock);
        dummyToken.approve(address(investmentManagerMock), type(uint256).max);
        dummyToken.approve(address(dummyStrat), type(uint256).max);
        investmentManager.depositIntoStrategy(dummyStrat, dummyToken, REQUIRED_BALANCE_WEI);


    }

    function testBeaconChainQueuedWithdrawalToDifferentAddress(address withdrawer) external {
        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](2);
        IERC20[] memory tokensArray = new IERC20[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        uint256[] memory strategyIndexes = new uint256[](1);
        bool undelegateIfPossible = false;

        {
            strategyArray[0] = investmentManager.beaconChainETHStrategy();
            shareAmounts[0] = REQUIRED_BALANCE_WEI;
            strategyIndexes[0] = 0;
        }

        IInvestmentManager.StratsTokensShares memory sts = IInvestmentManager.StratsTokensShares(strategyArray, tokensArray, shareAmounts);
        cheats.expectRevert(bytes("InvestmentManager.queueWithdrawal: cannot queue a withdrawal of Beacon Chain ETH to a different address"));
        investmentManagerMock.queueWithdrawal(strategyIndexes, sts, withdrawer, undelegateIfPossible);
    }

    function testQueuedWithdrawalsMultipleStrategiesWithBeaconChain() external {
        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](2);
        IERC20[] memory tokensArray = new IERC20[](2);
        uint256[] memory shareAmounts = new uint256[](2);
        uint256[] memory strategyIndexes = new uint256[](2);
        bool undelegateIfPossible = false;

        {
            strategyArray[0] = investmentManager.beaconChainETHStrategy();
            shareAmounts[0] = REQUIRED_BALANCE_WEI;
            strategyIndexes[0] = 0;
            strategyArray[1] = new InvestmentStrategyBase(investmentManagerMock);
            shareAmounts[1] = REQUIRED_BALANCE_WEI;
            strategyIndexes[1] = 1;
        }

        IInvestmentManager.StratsTokensShares memory sts = IInvestmentManager.StratsTokensShares(strategyArray, tokensArray, shareAmounts);
        cheats.expectRevert(bytes("InvestmentManager.queueWithdrawal: cannot queue a withdrawal including Beacon Chain ETH and other tokens"));
        investmentManagerMock.queueWithdrawal(strategyIndexes, sts, address(this), undelegateIfPossible);

        {
            strategyArray[0] = wethStrat;
            shareAmounts[0] = 1;
            strategyIndexes[0] = 0;
            strategyArray[1] = investmentManager.beaconChainETHStrategy();
            shareAmounts[1] = REQUIRED_BALANCE_WEI;
            strategyIndexes[1] = 1;
        }
        sts = IInvestmentManager.StratsTokensShares(strategyArray, tokensArray, shareAmounts);
        cheats.expectRevert(bytes("InvestmentManager.queueWithdrawal: cannot queue a withdrawal including Beacon Chain ETH and other tokens"));
        investmentManagerMock.queueWithdrawal(strategyIndexes, sts, address(this), undelegateIfPossible);
    }

    function testQueuedWithdrawalsNonWholeAmountGwei(uint256 nonWholeAmount) external {
        cheats.assume(nonWholeAmount % GWEI_TO_WEI != 0);
        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        uint256[] memory strategyIndexes = new uint256[](1);
        bool undelegateIfPossible = false;

        {
            strategyArray[0] = investmentManager.beaconChainETHStrategy();
            shareAmounts[0] = REQUIRED_BALANCE_WEI - 1243895959494;
            strategyIndexes[0] = 0;
        }

        IInvestmentManager.StratsTokensShares memory sts = IInvestmentManager.StratsTokensShares(strategyArray, tokensArray, shareAmounts);
        cheats.expectRevert(bytes("InvestmentManager.queueWithdrawal: cannot queue a withdrawal of Beacon Chain ETH for an non-whole amount of gwei"));
        investmentManagerMock.queueWithdrawal(strategyIndexes, sts, address(this), undelegateIfPossible);
    }

}