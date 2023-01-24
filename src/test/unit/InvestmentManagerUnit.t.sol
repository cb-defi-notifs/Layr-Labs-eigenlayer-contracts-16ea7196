// //SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "forge-std/Test.sol";

import "../../contracts/core/InvestmentManager.sol";
import "../mocks/DelegationMock.sol";
import "../mocks/SlasherMock.sol";
import "../EigenLayerTestHelper.t.sol";
import "../mocks/ERC20Mock.sol";


contract InvestmentManagerUnitTests is EigenLayerTestHelper {

    InvestmentManager investmentManagerMock;
    DelegationMock delegationMock;
    SlasherMock slasherMock;

    InvestmentStrategyBase dummyStrat;

    uint256 GWEI_TO_WEI = 1e9;

    function setUp() override virtual public{
        EigenLayerDeployer.setUp();

        
        slasherMock = new SlasherMock();
        delegationMock = new DelegationMock();
        investmentManagerMock = new InvestmentManager(delegationMock, eigenPodManager, slasherMock);
        IERC20 dummyToken = new ERC20Mock();
        InvestmentStrategyBase dummyStratImplementation = new InvestmentStrategyBase(investmentManagerMock);
        dummyStrat = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(dummyStratImplementation),
                    address(eigenLayerProxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, dummyToken, eigenLayerPauserReg)
                )
            )
        );

        // whitelist the strategy for deposit
        cheats.startPrank(investmentManagerMock.owner());
        IInvestmentStrategy[] memory _strategy = new IInvestmentStrategy[](1);
        _strategy[0] = dummyStrat;
        investmentManagerMock.addStrategiesToDepositWhitelist(_strategy);
        cheats.stopPrank();

        investmentManagerMock.depositIntoStrategy(dummyStrat, dummyToken, REQUIRED_BALANCE_WEI);
    }

    function testBeaconChainQueuedWithdrawalToDifferentAddress(address withdrawer) external {
        // filtering for test flakiness
        cheats.assume(withdrawer != address(this));

        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](2);
        uint256[] memory shareAmounts = new uint256[](1);
        uint256[] memory strategyIndexes = new uint256[](1);
        bool undelegateIfPossible = false;

        {
            strategyArray[0] = investmentManager.beaconChainETHStrategy();
            shareAmounts[0] = REQUIRED_BALANCE_WEI;
            strategyIndexes[0] = 0;
        }

        cheats.expectRevert(bytes("InvestmentManager.queueWithdrawal: cannot queue a withdrawal of Beacon Chain ETH to a different address"));
        investmentManagerMock.queueWithdrawal(strategyIndexes, strategyArray, shareAmounts, withdrawer, undelegateIfPossible);
    }

    function testQueuedWithdrawalsMultipleStrategiesWithBeaconChain() external {
        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](2);
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

        cheats.expectRevert(bytes("InvestmentManager.queueWithdrawal: cannot queue a withdrawal including Beacon Chain ETH and other tokens"));
        investmentManagerMock.queueWithdrawal(strategyIndexes, strategyArray, shareAmounts, address(this), undelegateIfPossible);

        {
            strategyArray[0] = dummyStrat;
            shareAmounts[0] = 1;
            strategyIndexes[0] = 0;
            strategyArray[1] = investmentManager.beaconChainETHStrategy();
            shareAmounts[1] = REQUIRED_BALANCE_WEI;
            strategyIndexes[1] = 1;
        }
        cheats.expectRevert(bytes("InvestmentManager.queueWithdrawal: cannot queue a withdrawal including Beacon Chain ETH and other tokens"));
        investmentManagerMock.queueWithdrawal(strategyIndexes, strategyArray, shareAmounts, address(this), undelegateIfPossible);
    }

    function testQueuedWithdrawalsNonWholeAmountGwei(uint256 nonWholeAmount) external {
        cheats.assume(nonWholeAmount % GWEI_TO_WEI != 0);
        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        uint256[] memory strategyIndexes = new uint256[](1);
        bool undelegateIfPossible = false;

        {
            strategyArray[0] = investmentManager.beaconChainETHStrategy();
            shareAmounts[0] = REQUIRED_BALANCE_WEI - 1243895959494;
            strategyIndexes[0] = 0;
        }

        cheats.expectRevert(bytes("InvestmentManager.queueWithdrawal: cannot queue a withdrawal of Beacon Chain ETH for an non-whole amount of gwei"));
        investmentManagerMock.queueWithdrawal(strategyIndexes, strategyArray, shareAmounts, address(this), undelegateIfPossible);
    }

}