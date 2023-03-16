// // SPDX-License-Identifier: UNLICENSED
// pragma solidity =0.8.12;


// import "forge-std/Test.sol";
// import "../contracts/pods/EigenPodV0.sol";
// import "../contracts/interfaces/IEigenPodV0.sol";
// import "../contracts/interfaces/IEigenPodManager.sol";
// import "./EigenLayerDeployer.t.sol";
// import "../contracts/pods/DelayedWithdrawalRouter.sol";
// import "./mocks/BeaconChainOracleMock.sol";
// import "./mocks/ServiceManagerMock.sol";





// contract EigenPodV0Test is Test {
//     using BytesLib for bytes;

//     uint256 internal constant GWEI_TO_WEI = 1e9;

//     bytes pubkey = hex"88347ed1c492eedc97fc8c506a35d44d81f27a0c7a1c661b35913cfd15256c0cccbd34a83341f505c7de2983292f2cab";
//     uint40 validatorIndex0 = 0;
//     uint40 validatorIndex1 = 1;
//     //hash tree root of list of validators
//     bytes32 validatorTreeRoot;

//     //hash tree root of individual validator container
//     bytes32 validatorRoot;

//     address podOwner = address(42000094993494);

//     Vm cheats = Vm(HEVM_ADDRESS);
//     PauserRegistry public pauserReg;
//     DelegationManager public delegation;
//     IStrategyManager public strategyManager;
//     Slasher public slasher;

//     ProxyAdmin public eigenLayerProxyAdmin;
//     IEigenPodManager public eigenPodManager;
//     IEigenPodV0 public podImplementation;
//     IDelayedWithdrawalRouter public delayedWithdrawalRouter;
//     IETHPOSDeposit public ethPOSDeposit;
//     IBeacon public eigenPodBeacon;
//     IBeaconChainOracle public beaconChainOracle;



    
//     address pauser = address(69);
//     address unpauser = address(489);
//     address podManagerAddress = 0x212224D2F2d262cd093eE13240ca4873fcCBbA3C;
//     address podAddress = address(123);
//     uint256 stakeAmount = 32e18;
//     mapping (address => bool) fuzzedAddressMapping;
//     bytes signature;
//     bytes32 depositDataRoot;
    
//     event EigenPodStaked(bytes pubkey);
//     event PaymentCreated(address podOwner, address recipient, uint256 amount);


//     modifier fuzzedAddress(address addr) virtual {
//         cheats.assume(fuzzedAddressMapping[addr] == false);
//         _;
//     }

//     uint32 PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS = 7 days / 12 seconds;

//     //performs basic deployment before each test
//     function setUp() public {
//         // deploy proxy admin for ability to upgrade proxy contracts
//         eigenLayerProxyAdmin = new ProxyAdmin();

//         // deploy pauser registry
//         pauserReg = new PauserRegistry(pauser, unpauser);

//         /**
//          * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
//          * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
//          */
//         EmptyContract emptyContract = new EmptyContract();
//         delegation = DelegationManager(
//             address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
//         );
//         strategyManager = StrategyManager(
//             address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
//         );
//         slasher = Slasher(
//             address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
//         );
//         delayedWithdrawalRouter = DelayedWithdrawalRouter(
//             address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
//         );

//         ethPOSDeposit = new ETHPOSDepositMock();
//         podImplementation = new EigenPodV0(
//                 ethPOSDeposit, 
//                 delayedWithdrawalRouter
//         );

//         eigenPodBeacon = new UpgradeableBeacon(address(podImplementation));

//         // this contract is deployed later to keep its address the same (for these tests)
//         eigenPodManager = EigenPodManager(
//             address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
//         );

//         // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
//         DelegationManager delegationImplementation = new DelegationManager(strategyManager, slasher);
//         StrategyManager strategyManagerImplementation = new StrategyManager(delegation, IEigenPodManager(podManagerAddress), slasher);
//         Slasher slasherImplementation = new Slasher(strategyManager, delegation);
//         EigenPodManager eigenPodManagerImplementation = new EigenPodManager(ethPOSDeposit, eigenPodBeacon, strategyManager, slasher);

//         beaconChainOracle = new BeaconChainOracleMock();
//         DelayedWithdrawalRouter delayedWithdrawalRouterImplementation = new DelayedWithdrawalRouter(eigenPodManager);

//         address initialOwner = address(this);
//         // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
//         eigenLayerProxyAdmin.upgradeAndCall(
//             TransparentUpgradeableProxy(payable(address(delegation))),
//             address(delegationImplementation),
//             abi.encodeWithSelector(DelegationManager.initialize.selector, pauserReg, initialOwner)
//         );
//         eigenLayerProxyAdmin.upgradeAndCall(
//             TransparentUpgradeableProxy(payable(address(strategyManager))),
//             address(strategyManagerImplementation),
//             abi.encodeWithSelector(StrategyManager.initialize.selector, pauserReg, initialOwner, 0)
//         );
//         eigenLayerProxyAdmin.upgradeAndCall(
//             TransparentUpgradeableProxy(payable(address(slasher))),
//             address(slasherImplementation),
//             abi.encodeWithSelector(Slasher.initialize.selector, pauserReg, initialOwner)
//         );
//         eigenLayerProxyAdmin.upgradeAndCall(
//             TransparentUpgradeableProxy(payable(address(eigenPodManager))),
//             address(eigenPodManagerImplementation),
//             abi.encodeWithSelector(EigenPodManager.initialize.selector, beaconChainOracle, initialOwner, pauserReg, 0)
//         );
//         uint256 initPausedStatus = 0;
//         uint256 withdrawalDelayBlocks = PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS;
//         eigenLayerProxyAdmin.upgradeAndCall(
//             TransparentUpgradeableProxy(payable(address(delayedWithdrawalRouter))),
//             address(delayedWithdrawalRouterImplementation),
//             abi.encodeWithSelector(DelayedWithdrawalRouter.initialize.selector, initialOwner, pauserReg, initPausedStatus, withdrawalDelayBlocks)
//         );

//         cheats.deal(address(podOwner), stakeAmount);     

//         fuzzedAddressMapping[address(0)] = true;
//         fuzzedAddressMapping[address(eigenLayerProxyAdmin)] = true;
//         fuzzedAddressMapping[address(strategyManager)] = true;
//         fuzzedAddressMapping[address(eigenPodManager)] = true;
//         fuzzedAddressMapping[address(slasher)] = true;


//     }

//     function testStaking() public {
//         cheats.startPrank(podOwner);
//         cheats.expectEmit(true, false, false, false);
//         emit EigenPodStaked(pubkey);
//         eigenPodManager.stake{value: stakeAmount}(pubkey, signature, depositDataRoot);
//         cheats.stopPrank();
//     }

//     function testWithdrawFromPod() public {
//         cheats.startPrank(podOwner);
//         eigenPodManager.stake{value: stakeAmount}(pubkey, signature, depositDataRoot);
//         cheats.stopPrank();

//         address pod = address(eigenPodManager.getPod(podOwner));
//         uint256 balance = pod.balance;
//         cheats.deal(pod, stakeAmount);

//         cheats.startPrank(podOwner);
//         cheats.expectEmit(true, false, false, false);
//         emit PaymentCreated(podOwner, podOwner, balance);
//         IEigenPodV0(pod).withdraw();
//         cheats.stopPrank();
//         require(address(pod).balance == 0, "Pod balance should be 0");
        
//     }

// }

