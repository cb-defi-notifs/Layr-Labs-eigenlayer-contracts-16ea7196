// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "../contracts/interfaces/IEigenLayrDelegation.sol";
import "../contracts/core/EigenLayrDelegation.sol";

import "../contracts/interfaces/IETHPOSDeposit.sol";
import "../contracts/interfaces/IBeaconChainOracle.sol";

import "../contracts/core/InvestmentManager.sol";
import "../contracts/strategies/InvestmentStrategyBase.sol";
import "../contracts/core/Slasher.sol";

import "../contracts/pods/EigenPod.sol";
import "../contracts/pods/EigenPodManager.sol";

import "../contracts/permissions/PauserRegistry.sol";

import "../contracts/DataLayr/DataLayrServiceManager.sol";
import "../contracts/DataLayr/BLSRegistryWithBomb.sol";
import "../contracts/middleware/BLSPublicKeyCompendium.sol";
import "../contracts/DataLayr/DataLayrPaymentManager.sol";
import "../contracts/DataLayr/EphemeralKeyRegistry.sol";
import "../contracts/DataLayr/DataLayrChallengeUtils.sol";
import "../contracts/DataLayr/DataLayrLowDegreeChallenge.sol";

import "../contracts/libraries/BLS.sol";
import "../contracts/libraries/BytesLib.sol";
import "../contracts/libraries/DataStoreUtils.sol";

import "./utils/Signers.sol";
import "./utils/SignatureUtils.sol";

import "./mocks/LiquidStakingToken.sol";
import "./mocks/EmptyContract.sol";
import "./mocks/BeaconChainOracleMock.sol";
import "./mocks/ETHDepositMock.sol";

 import "forge-std/Test.sol";

contract EigenLayrDeployer is Signers, SignatureUtils, DSTest {
    using BytesLib for bytes;

    Vm cheats = Vm(HEVM_ADDRESS);

    // EigenLayer contracts
    ProxyAdmin public eigenLayrProxyAdmin;
    PauserRegistry public eigenLayrPauserReg;

    Slasher public slasher;
    EigenLayrDelegation public delegation;
    InvestmentManager public investmentManager;
    IEigenPodManager public eigenPodManager;
    IEigenPod public pod;
    IETHPOSDeposit public ethPOSDeposit;
    IBeacon public eigenPodBeacon;
    IBeaconChainOracle public beaconChainOracle;

    // testing/mock contracts
    IERC20 public eigenToken;
    IERC20 public weth;
    WETH public liquidStakingMockToken;
    InvestmentStrategyBase public wethStrat;
    InvestmentStrategyBase public eigenStrat;
    InvestmentStrategyBase public liquidStakingMockStrat;
    InvestmentStrategyBase public baseStrategyImplementation;
    EmptyContract public emptyContract;

    IVoteWeigher public generalVoteWeigher;

    mapping(uint256 => IInvestmentStrategy) public strategies;
    mapping(IInvestmentStrategy => uint256) public initialOperatorShares;

    //from testing seed phrase
    bytes32 priv_key_0 = 0x1234567812345678123456781234567812345678123456781234567812345678;
    bytes32 priv_key_1 = 0x1234567812345678123456781234567812345698123456781234567812348976;
    bytes32 public testEphemeralKey = 0x3290567812345678123456781234577812345698123456781234567812344389;
    bytes32 public testEphemeralKeyHash = keccak256(abi.encode(testEphemeralKey));

    string testSocket = "255.255.255.255";

    // number of strategies deployed
    uint256 public numberOfStrats;
    //strategy indexes for undelegation (see commitUndelegation function)
    uint256[] public strategyIndexes;
    address[2] public delegates;
    address sample_registrant = cheats.addr(436364636);

    uint256[] apks;
    uint256[] sigmas;

    address[] public slashingContracts;

    uint256 wethInitialSupply = 10e50;
    uint256 public constant eigenTotalSupply = 1000e18;
    uint256 nonce = 69;
    uint256 public gasLimit = 750000;

    address pauser = address(69);
    address unpauser = address(489);
    address operator = address(0x4206904396bF2f8b173350ADdEc5007A52664293); //sk: e88d9d864d5d731226020c5d2f02b62a4ce2a4534a39c225d32d3db795f83319
    address acct_0 = cheats.addr(uint256(priv_key_0));
    address acct_1 = cheats.addr(uint256(priv_key_1));
    address _challenger = address(0x6966904396bF2f8b173350bCcec5007A52669873);

    bytes header = hex"0e75f28b7a90f89995e522d0cd3a340345e60e249099d4cd96daef320a3abfc31df7f4c8f6f8bc5dc1de03f56202933ec2cc40acad1199f40c7b42aefd45bfb10000000800000002000000020000014000000000000000000000000000000000000000002b4982b07d4e522c2a94b3e7c5ab68bfeecc33c5fa355bc968491c62c12cf93f0cd04099c3d9742620bf0898cf3843116efc02e6f7d408ba443aa472f950e4f3";

    address initialOwner = address(this);

    modifier fuzzedAddress(address addr) virtual {
        cheats.assume(addr != address(0));
        cheats.assume(addr != address(eigenLayrProxyAdmin));
        cheats.assume(addr != address(investmentManager));
        _;
    }

    modifier cannotReinit() {
        cheats.expectRevert(bytes("Initializable: contract is already initialized"));
        _;
    }

    //performs basic deployment before each test
    function setUp() public virtual {
        _deployEigenLayrContracts();
        _setUpSignersAndSignatures();
    }

    function _deployEigenLayrContracts() internal {
        // deploy proxy admin for ability to upgrade proxy contracts
        eigenLayrProxyAdmin = new ProxyAdmin();

        //deploy pauser registry
        eigenLayrPauserReg = new PauserRegistry(pauser, unpauser);

        /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        emptyContract = new EmptyContract();
        delegation = EigenLayrDelegation(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );
        investmentManager = InvestmentManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );
        slasher = Slasher(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );
        eigenPodManager = EigenPodManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );

        beaconChainOracle = new BeaconChainOracleMock();
        beaconChainOracle.setBeaconChainStateRoot(0xb08d5a1454de19ac44d523962096d73b85542f81822c5e25b8634e4e86235413);

        ethPOSDeposit = new ETHPOSDepositMock();
        pod = new EigenPod(ethPOSDeposit);

        eigenPodBeacon = new UpgradeableBeacon(address(pod));

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        EigenLayrDelegation delegationImplementation = new EigenLayrDelegation(investmentManager);
        InvestmentManager investmentManagerImplementation = new InvestmentManager(delegation, eigenPodManager, slasher);
        Slasher slasherImplementation = new Slasher(investmentManager, delegation);
        EigenPodManager eigenPodManagerImplementation = new EigenPodManager(ethPOSDeposit, eigenPodBeacon, investmentManager);


        // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(delegation))),
            address(delegationImplementation),
            abi.encodeWithSelector(EigenLayrDelegation.initialize.selector, eigenLayrPauserReg, initialOwner)
        );
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(investmentManager))),
            address(investmentManagerImplementation),
            abi.encodeWithSelector(InvestmentManager.initialize.selector, eigenLayrPauserReg, initialOwner)
        );
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(slasher))),
            address(slasherImplementation),
            abi.encodeWithSelector(Slasher.initialize.selector, eigenLayrPauserReg, initialOwner)
        );
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(eigenPodManager))),
            address(eigenPodManagerImplementation),
            abi.encodeWithSelector(EigenPodManager.initialize.selector, beaconChainOracle, initialOwner)
        );


        //simple ERC20 (**NOT** WETH-like!), used in a test investment strategy
        weth = new ERC20PresetFixedSupply(
            "weth",
            "WETH",
            wethInitialSupply,
            address(this)
        );

        // deploy InvestmentStrategyBase contract implementation, then create upgradeable proxy that points to implementation and initialize it
        baseStrategyImplementation = new InvestmentStrategyBase(investmentManager);
        wethStrat = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(baseStrategyImplementation),
                    address(eigenLayrProxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, weth, eigenLayrPauserReg)
                )
            )
        );

        eigenToken = new ERC20PresetFixedSupply(
            "eigen",
            "EIGEN",
            wethInitialSupply,
            address(this)
        );

        // deploy upgradeable proxy that points to InvestmentStrategyBase implementation and initialize it
        eigenStrat = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(baseStrategyImplementation),
                    address(eigenLayrProxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, eigenToken, eigenLayrPauserReg)
                )
            )
        );

        delegates = [acct_0, acct_1];

        // set up a strategy for a mock liquid staking token
        liquidStakingMockToken = new WETH();
        liquidStakingMockStrat = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(baseStrategyImplementation),
                    address(eigenLayrProxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, liquidStakingMockToken, eigenLayrPauserReg)
                )
            )
        );

        slashingContracts.push(address(eigenPodManager));
        investmentManager.slasher().addGloballyPermissionedContracts(slashingContracts);
    }

    function _setUpSignersAndSignatures() internal {
        //loads hardcoded signer set
        _setSigners();

        //loads signatures
        setSignatures();
    }
}
