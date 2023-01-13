// //SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../contracts/strategies/InvestmentStrategyBase.sol";
import "../../contracts/permissions/PauserRegistry.sol";

import "../mocks/InvestmentManagerMock.sol";

import "forge-std/Test.sol";

contract InvestmentStrategyBaseUnitTests is Test {

    Vm cheats = Vm(HEVM_ADDRESS);

    ProxyAdmin public proxyAdmin;
    PauserRegistry public pauserRegistry;
    IInvestmentManager public investmentManager;
    IERC20 public underlyingToken;
    InvestmentStrategyBase public investmentStrategy;

    address public pauser = address(555);
    address public unpauser = address(999);

    function setUp() virtual public {
        proxyAdmin = new ProxyAdmin();

        pauserRegistry = new PauserRegistry(pauser, unpauser);

        investmentManager = new InvestmentManagerMock(
            IEigenLayerDelegation(address(this)),
            IEigenPodManager(address(this)),
            ISlasher(address(this))
        );

        uint256 initialSupply = 1e24;
        address owner = address(this);
        underlyingToken = new ERC20PresetFixedSupply("Test Token", "TEST", initialSupply, owner);

        InvestmentStrategyBase investmentStrategyImplementation = new InvestmentStrategyBase(investmentManager);

        investmentStrategy = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(investmentStrategyImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, underlyingToken, pauserRegistry)
                )
            )
        );
    }

    function testCannotReinitialize() public {
        cheats.expectRevert(bytes("Initializable: contract is already initialized"));
        investmentStrategy.initialize(underlyingToken, pauserRegistry);
    }

    function testDepositWithZeroPriorBalanceAndZeroPriorShares(uint256 amountToDeposit) public {
        // sanity check / filter
        cheats.assume(amountToDeposit <= underlyingToken.balanceOf(address(this)));

        uint256 totalSharesBefore = investmentStrategy.totalShares();

        underlyingToken.transfer(address(investmentStrategy), amountToDeposit);

        cheats.startPrank(address(investmentManager));
        uint256 newShares = investmentStrategy.deposit(underlyingToken, amountToDeposit);
        cheats.stopPrank();

        require(newShares == amountToDeposit, "newShares != amountToDeposit");
        uint256 totalSharesAfter = investmentStrategy.totalShares();
        require(totalSharesAfter - totalSharesBefore == newShares, "totalSharesAfter - totalSharesBefore != newShares");
    }

    function testDepositWithNonzeroPriorBalanceAndNonzeroPriorShares(uint256 priorTotalShares, uint256 amountToDeposit) public {
        testDepositWithZeroPriorBalanceAndZeroPriorShares(priorTotalShares);

        // sanity check / filter
        cheats.assume(amountToDeposit <= underlyingToken.balanceOf(address(this)));

        uint256 totalSharesBefore = investmentStrategy.totalShares();

        underlyingToken.transfer(address(investmentStrategy), amountToDeposit);

        cheats.startPrank(address(investmentManager));
        uint256 newShares = investmentStrategy.deposit(underlyingToken, amountToDeposit);
        cheats.stopPrank();

        require(newShares == amountToDeposit, "newShares != amountToDeposit");
        uint256 totalSharesAfter = investmentStrategy.totalShares();
        require(totalSharesAfter - totalSharesBefore == newShares, "totalSharesAfter - totalSharesBefore != newShares");
    }

    function testDepositFailsWhenDepositsPaused() public {
        cheats.startPrank(pauser);
        investmentStrategy.pause(type(uint256).max);
        cheats.stopPrank();

        uint256 amountToDeposit = 1e18;
        underlyingToken.transfer(address(investmentStrategy), amountToDeposit);

        cheats.expectRevert(bytes("Pausable: index is paused"));
        cheats.startPrank(address(investmentManager));
        investmentStrategy.deposit(underlyingToken, amountToDeposit);
        cheats.stopPrank();
    }

    function testDepositFailsWhenCallingFromNotInvestmentManager(address caller) public {
        cheats.assume(caller != address(investmentStrategy.investmentManager()) && caller != address(proxyAdmin));

        uint256 amountToDeposit = 1e18;
        underlyingToken.transfer(address(investmentStrategy), amountToDeposit);

        cheats.expectRevert(bytes("InvestmentStrategyBase.onlyInvestmentManager"));
        cheats.startPrank(caller);
        investmentStrategy.deposit(underlyingToken, amountToDeposit);
        cheats.stopPrank();
    }

    function testWithdrawWithPriorTotalSharesAndAmountSharesEqual(uint256 amountToDeposit) public {
        testDepositWithZeroPriorBalanceAndZeroPriorShares(amountToDeposit);

        uint256 sharesToWithdraw = investmentStrategy.totalShares();
        uint256 strategyBalanceBefore = underlyingToken.balanceOf(address(investmentStrategy));

        uint256 tokenBalanceBefore = underlyingToken.balanceOf(address(this));
        cheats.startPrank(address(investmentManager));
        investmentStrategy.withdraw(address(this), underlyingToken, sharesToWithdraw);
        cheats.stopPrank();

        uint256 tokenBalanceAfter = underlyingToken.balanceOf(address(this));
        uint256 totalSharesAfter = investmentStrategy.totalShares();

        require(totalSharesAfter == 0, "shares did not decrease appropriately");
        require(tokenBalanceAfter - tokenBalanceBefore == strategyBalanceBefore, "tokenBalanceAfter - tokenBalanceBefore != strategyBalanceBefore");
    }

    function testWithdrawWithPriorTotalSharesAndAmountSharesNotEqual(uint256 amountToDeposit, uint256 sharesToWithdraw) public {
        testDepositWithZeroPriorBalanceAndZeroPriorShares(amountToDeposit);

        uint256 totalSharesBefore = investmentStrategy.totalShares();
        uint256 strategyBalanceBefore = underlyingToken.balanceOf(address(investmentStrategy));

        // since we are checking not equal in this test
        cheats.assume(sharesToWithdraw < totalSharesBefore);

        uint256 tokenBalanceBefore = underlyingToken.balanceOf(address(this));

        cheats.startPrank(address(investmentManager));
        investmentStrategy.withdraw(address(this), underlyingToken, sharesToWithdraw);
        cheats.stopPrank();

        uint256 tokenBalanceAfter = underlyingToken.balanceOf(address(this));
        uint256 totalSharesAfter = investmentStrategy.totalShares();

        require(totalSharesBefore - totalSharesAfter == sharesToWithdraw, "shares did not decrease appropriately");
        require(tokenBalanceAfter - tokenBalanceBefore == (strategyBalanceBefore * sharesToWithdraw) / totalSharesBefore,
            "token balance did not increase appropriately");
    }
}