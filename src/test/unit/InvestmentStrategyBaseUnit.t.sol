// //SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../contracts/strategies/InvestmentStrategyBase.sol";
import "../../contracts/permissions/PauserRegistry.sol";

// import "../mocks/InvestmentManagerMock.sol";

import "forge-std/Test.sol";

contract InvestmentStrategyBaseUnitTests is Test {

    Vm cheats = Vm(HEVM_ADDRESS);

    ProxyAdmin public proxyAdmin;
    PauserRegistry public pauserRegistry;
    // IInvestmentManager public investmentManagerMock;
    IInvestmentManager public investmentManagerMock = IInvestmentManager(address(this));
    IERC20 public tokenMock;
    InvestmentStrategyBase public investmentStrategy;

    address public pauser = address(555);
    address public unpauser = address(999);

    function setUp() virtual public {
        proxyAdmin = new ProxyAdmin();

        pauserRegistry = new PauserRegistry(pauser, unpauser);

        // investmentManagerMock = new InvestmentManagerMock(
        //     IEigenLayerDelegation(address(this)),
        //     IEigenPodManager(address(this)),
        //     ISlasher(address(this))
        // );

        uint256 initialSupply = 1e24;
        address owner = address(this);
        tokenMock = new ERC20PresetFixedSupply("Test Token", "TEST", initialSupply, owner);

        // InvestmentStrategyBase investmentStrategyImplementation = new InvestmentStrategyBase(investmentManagerMock);
        InvestmentStrategyBase investmentStrategyImplementation = new InvestmentStrategyBase(investmentManagerMock);

        investmentStrategy = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(investmentStrategyImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, tokenMock, pauserRegistry)
                )
            )
        );
    }

    function testCannotReinitialize() public {
        cheats.expectRevert(bytes("Initializable: contract is already initialized"));
        investmentStrategy.initialize(tokenMock, pauserRegistry);
    }

}