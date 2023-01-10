// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../src/contracts/interfaces/IInvestmentManager.sol";
import "../../src/contracts/interfaces/IInvestmentStrategy.sol";
import "../../src/contracts/interfaces/IEigenLayrDelegation.sol";
import "../../src/contracts/strategies/InvestmentStrategyBase.sol";
import "../../src/contracts/middleware/BLSRegistry.sol";

import "../../src/test/mocks/ServiceManagerMock.sol";
import "../../src/test/mocks/PublicKeyCompendiumMock.sol";


import "../../script/whitelist/ERC20PresetMinterPauser.sol";

import "../../script/whitelist/Staker.sol";
import "../../script/whitelist/Whitelister.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

import "./EigenLayrDeployer.t.sol";

import "forge-std/Test.sol";

contract WhitelisterTests is EigenLayrDeployer {

    ERC20PresetMinterPauser dummyToken;
    IInvestmentStrategy dummyStrat;
    IInvestmentStrategy dummyStratImplementation;
    Whitelister whiteLister;

    BLSRegistry blsRegistry;
    BLSRegistry blsRegistryImplementation;


    ServiceManagerMock dummyServiceManager;
    BLSPublicKeyCompendiumMock dummyCompendium;



    address theMultiSig = address(420);

    function setUp() public virtual override{
        EigenLayrDeployer.setUp();


        emptyContract = new EmptyContract();
        blsRegistry = BLSRegistry(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );

        dummyToken = new ERC20PresetMinterPauser("dummy staked ETH", "dsETH");
        dummyStratImplementation = new InvestmentStrategyBase(investmentManager);
        dummyStrat = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                        address(dummyStratImplementation),
                        address(eigenLayrProxyAdmin),
                        abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, dummyToken, eigenLayrPauserReg)
                    )
                )
        );

        whiteLister = new Whitelister(investmentManager, delegation, dummyToken, dummyStrat, blsRegistry);
        whiteLister.transferOwnership(theMultiSig);

        dummyToken.grantRole(keccak256("MINTER_ROLE"), address(whiteLister));
        dummyToken.grantRole(keccak256("PAUSER_ROLE"), address(whiteLister));  

        dummyToken.grantRole(keccak256("MINTER_ROLE"), theMultiSig);
        dummyToken.grantRole(keccak256("PAUSER_ROLE"), theMultiSig);

        dummyToken.revokeRole(keccak256("MINTER_ROLE"), address(this));  
        dummyToken.revokeRole(keccak256("PAUSER_ROLE"), address(this));  


        dummyServiceManager  = new ServiceManagerMock(investmentManager);
        blsRegistryImplementation = new BLSRegistry(delegation, investmentManager, dummyServiceManager, 2, dummyCompendium);

        uint256[] memory _quorumBips = new uint256[](2);
        // split 60% ETH quorum, 40% EIGEN quorum
        _quorumBips[0] = 6000;
        _quorumBips[1] = 4000;

        VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[] memory ethStratsAndMultipliers =
                new VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[](1);
            ethStratsAndMultipliers[0].strategy = wethStrat;
            ethStratsAndMultipliers[0].multiplier = 1e18;
        VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[] memory eigenStratsAndMultipliers =
                new VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[](1);
            eigenStratsAndMultipliers[0].strategy = eigenStrat;
            eigenStratsAndMultipliers[0].multiplier = 1e18;

        eigenLayrProxyAdmin.upgradeAndCall(
                TransparentUpgradeableProxy(payable(address(blsRegistry))),
                address(blsRegistryImplementation),
                abi.encodeWithSelector(BLSRegistry.initialize.selector, address(whiteLister), true, _quorumBips, ethStratsAndMultipliers, eigenStratsAndMultipliers)
            );

    }

    function testWhitelistingOperator(address operator) public fuzzedAddress(operator){
        cheats.startPrank(operator);
        IDelegationTerms dt = IDelegationTerms(address(89));
        delegation.registerAsOperator(dt);
        cheats.stopPrank();

        cheats.startPrank(theMultiSig);
        whiteLister.whitelist(operator);
        cheats.stopPrank();

        assertTrue(blsRegistry.whitelisted(operator) == true, "operator not added to whitelist");
    }

    function testDepositIntoStrategy(address operator) external fuzzedAddress(operator){
        testWhitelistingOperator(operator);

        cheats.startPrank(theMultiSig);
        address staker = whiteLister.getStaker(operator);
         dummyToken.mint(staker, 10e18);
         emit log_named_uint("staker balance", dummyToken.balanceOf(staker));
        uint256 amount = 200;
        whiteLister.depositIntoStrategy(staker, dummyStrat, dummyToken, amount);
        cheats.stopPrank();
    }

}