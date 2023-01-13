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

    }

}