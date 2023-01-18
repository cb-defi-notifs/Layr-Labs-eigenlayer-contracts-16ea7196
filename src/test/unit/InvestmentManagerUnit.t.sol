// //SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "forge-std/Test.sol";

import "../../contracts/core/InvestmentManager.sol";
import "../../contracts/strategies/InvestmentStrategyBase.sol";
import "../../contracts/permissions/PauserRegistry.sol";
import "../mocks/DelegationMock.sol";
import "../mocks/SlasherMock.sol";
import "../mocks/EigenPodManagerMock.sol";


import "../mocks/ERC20Mock.sol";


contract InvestmentManagerUnitTests is Test {

    Vm cheats = Vm(HEVM_ADDRESS);

    uint256 public REQUIRED_BALANCE_WEI = 31.4 ether;

    ProxyAdmin public proxyAdmin;
    PauserRegistry public pauserRegistry;

    InvestmentManager public investmentManagerImplementation;
    InvestmentManager public investmentManager;
    DelegationMock public delegationMock;
    SlasherMock public slasherMock;
    EigenPodManagerMock public eigenPodManagerMock;

    InvestmentStrategyBase public dummyStrat;

    IInvestmentStrategy public beaconChainETHStrategy;

    IERC20 public dummyToken;

    uint256 GWEI_TO_WEI = 1e9;

    address public pauser = address(555);
    address public unpauser = address(999);

    address initialOwner = address(this);

    function setUp() virtual public {
        proxyAdmin = new ProxyAdmin();

        pauserRegistry = new PauserRegistry(pauser, unpauser);

        slasherMock = new SlasherMock();
        delegationMock = new DelegationMock();
        eigenPodManagerMock = new EigenPodManagerMock();
        investmentManagerImplementation = new InvestmentManager(delegationMock, eigenPodManagerMock, slasherMock);
        investmentManager = InvestmentManager(
            address(
                new TransparentUpgradeableProxy(
                    address(investmentManagerImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(InvestmentManager.initialize.selector, pauserRegistry, initialOwner)
                )
            )
        );
        dummyToken = new ERC20Mock();
        InvestmentStrategyBase dummyStratImplementation = new InvestmentStrategyBase(investmentManager);
        dummyStrat = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(dummyStratImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, dummyToken, pauserRegistry)
                )
            )
        );

        investmentManager.depositIntoStrategy(dummyStrat, dummyToken, REQUIRED_BALANCE_WEI);
        beaconChainETHStrategy = investmentManager.beaconChainETHStrategy();

    }

    function testCannotReinitialize() public {
        cheats.expectRevert(bytes("Initializable: contract is already initialized"));
        investmentManager.initialize(pauserRegistry, initialOwner);
    }

    function testDepositBeaconChainETHSuccessfully(uint256 amount) public {
        // fitler out zero case since it will revert with "InvestmentManager._addShares: shares should not be zero!"
        cheats.assume(amount != 0);
        uint256 sharesBefore = investmentManager.investorStratShares(address(this), beaconChainETHStrategy);

        cheats.startPrank(address(eigenPodManagerMock));
        investmentManager.depositBeaconChainETH(address(this), amount);
        cheats.stopPrank();

        uint256 sharesAfter = investmentManager.investorStratShares(address(this), beaconChainETHStrategy);
        require(sharesAfter == sharesBefore + amount, "sharesAfter != sharesBefore + amount");
    }

    function testDepositBeaconChainETHFailsWhenDepositsPaused() public {
        uint256 amount = 1e18;
        address staker = address(this);

        // pause deposits
        cheats.startPrank(pauser);
        investmentManager.pause(1);
        cheats.stopPrank();

        cheats.expectRevert(bytes("Pausable: index is paused"));
        cheats.startPrank(address(eigenPodManagerMock));
        investmentManager.depositBeaconChainETH(staker, amount);
        cheats.stopPrank();
    }

    function testDepositBeaconChainETHFailsWhenStakerFrozen() public {
        uint256 amount = 1e18;
        address staker = address(this);

        // slash this contract (the staker)
        slasherMock.freezeOperator(staker);

        cheats.expectRevert(bytes("InvestmentManager.onlyNotFrozen: staker has been frozen and may be subject to slashing"));
        cheats.startPrank(address(eigenPodManagerMock));
        investmentManager.depositBeaconChainETH(staker, amount);
        cheats.stopPrank();
    }


    function testBeaconChainQueuedWithdrawalToDifferentAddress(address withdrawer) external {
        // filtering for test flakiness
        cheats.assume(withdrawer != address(this));

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
        investmentManager.queueWithdrawal(strategyIndexes, sts, withdrawer, undelegateIfPossible);
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
            strategyArray[1] = new InvestmentStrategyBase(investmentManager);
            shareAmounts[1] = REQUIRED_BALANCE_WEI;
            strategyIndexes[1] = 1;
        }

        IInvestmentManager.StratsTokensShares memory sts = IInvestmentManager.StratsTokensShares(strategyArray, tokensArray, shareAmounts);
        cheats.expectRevert(bytes("InvestmentManager.queueWithdrawal: cannot queue a withdrawal including Beacon Chain ETH and other tokens"));
        investmentManager.queueWithdrawal(strategyIndexes, sts, address(this), undelegateIfPossible);

        {
            strategyArray[0] = dummyStrat;
            shareAmounts[0] = 1;
            strategyIndexes[0] = 0;
            strategyArray[1] = investmentManager.beaconChainETHStrategy();
            shareAmounts[1] = REQUIRED_BALANCE_WEI;
            strategyIndexes[1] = 1;
        }
        sts = IInvestmentManager.StratsTokensShares(strategyArray, tokensArray, shareAmounts);
        cheats.expectRevert(bytes("InvestmentManager.queueWithdrawal: cannot queue a withdrawal including Beacon Chain ETH and other tokens"));
        investmentManager.queueWithdrawal(strategyIndexes, sts, address(this), undelegateIfPossible);
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
        investmentManager.queueWithdrawal(strategyIndexes, sts, address(this), undelegateIfPossible);
    }

}