// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./EigenLayrTestHelper.t.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../contracts/libraries/BytesLib.sol";

import "./mocks/MiddlewareVoteWeigherMock.sol";
import "./mocks/ServiceManagerMock.sol";
import "./mocks/PublicKeyCompendiumMock.sol";

import "../../src/contracts/middleware/BLSRegistry.sol";
import "../../src/contracts/middleware/BLSPublicKeyCompendium.sol";



contract RegistrationTests is EigenLayrTestHelper {

    BLSRegistry public dlRegImplementation;
    BLSPublicKeyCompendiumMock public pubkeyCompendium;

    BLSPublicKeyCompendiumMock public pubkeyCompendiumImplementation;
    BLSRegistry public dlReg;
    ProxyAdmin public dataLayrProxyAdmin;

    ServiceManagerMock public dlsm;




    function setUp() public virtual override {
        EigenLayrDeployer.setUp();

        initializeMiddlewares();
    }


    function initializeMiddlewares() public {
        dataLayrProxyAdmin = new ProxyAdmin();

        pubkeyCompendium = new BLSPublicKeyCompendiumMock();

        dlReg = BLSRegistry(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(dataLayrProxyAdmin), ""))
        );

        dlRegImplementation = new BLSRegistry(
                investmentManager,
                dlsm,
                2,
                pubkeyCompendium
            );

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
        
        dataLayrProxyAdmin.upgradeAndCall(
                TransparentUpgradeableProxy(payable(address(dlReg))),
                address(dlRegImplementation),
                abi.encodeWithSelector(BLSRegistry.initialize.selector, _quorumBips, ethStratsAndMultipliers, eigenStratsAndMultipliers)
            );

    }


    function testRegisterOperator(address operator, BN254.G1Point memory pk, string calldata socket) public fuzzedAddress(operator){

        //register as both ETH and EIGEN operator
        uint256 wethToDeposit = 1e18;
        uint256 eigenToDeposit = 1e10;
        _testDepositWeth(operator, wethToDeposit);
        _testDepositEigen(operator, eigenToDeposit);
        _testRegisterAsOperator(operator, IDelegationTerms(operator));


        cheats.startPrank(operator);
        pubkeyCompendium.registerPublicKey(pk);
        dlReg.registerOperator(1, pk, socket);
        cheats.stopPrank();

    }


}