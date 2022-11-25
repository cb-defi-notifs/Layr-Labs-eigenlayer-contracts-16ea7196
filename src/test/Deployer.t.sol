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

import "./utils/Operators.sol";
import "./utils/SignatureUtils.sol";

import "./mocks/LiquidStakingToken.sol";
import "./mocks/EmptyContract.sol";
import "./mocks/BeaconChainOracleMock.sol";
import "./mocks/ETHDepositMock.sol";


contract EigenLayrDeployer is Operators, SignatureUtils {
    using BytesLib for bytes;

    uint256 public constant DURATION_SCALE = 1 hours;
    uint32 public constant MAX_WITHDRAWAL_PERIOD = 7 days;

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

    // DataLayr contracts
    ProxyAdmin public dataLayrProxyAdmin;
    PauserRegistry public dataLayrPauserReg;

    DataLayrChallengeUtils public challengeUtils;
    EphemeralKeyRegistry public ephemeralKeyRegistry;
    BLSPublicKeyCompendium public pubkeyCompendium;
    BLSRegistryWithBomb public dlReg;
    DataLayrServiceManager public dlsm;
    DataLayrLowDegreeChallenge public dlldc;
    DataLayrPaymentManager public dataLayrPaymentManager;

    DataLayrChallengeUtils public challengeUtilsImplementation;
    EphemeralKeyRegistry public ephemeralKeyRegistryImplementation;
    BLSPublicKeyCompendium public pubkeyCompendiumImplementation;
    BLSRegistryWithBomb public dlRegImplementation;
    DataLayrServiceManager public dlsmImplementation;
    DataLayrLowDegreeChallenge public dlldcImplementation;
    DataLayrPaymentManager public dataLayrPaymentManagerImplementation;

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
    bytes[] registrationData;
    bytes32[] ephemeralKeyHashes;
    address[2] public delegates;
    uint256[] sample_pk;
    uint256[] sample_sig;
    address sample_registrant = cheats.addr(436364636);

    address[] public slashingContracts;

    uint256 wethInitialSupply = 10e50;
    uint256 undelegationFraudproofInterval = 7 days;
    uint256 public constant eigenTokenId = 0;
    uint256 public constant eigenTotalSupply = 1000e18;
    uint256 nonce = 69;
    uint256 public gasLimit = 750000;

    address podManagerAddress = 0x1d1499e622D69689cdf9004d05Ec547d650Ff211;              
    address storer = address(420);
    address pauser = address(69);
    address unpauser = address(489);
    address operator = address(0x4206904396bF2f8b173350ADdEc5007A52664293); //sk: e88d9d864d5d731226020c5d2f02b62a4ce2a4534a39c225d32d3db795f83319
    address acct_0 = cheats.addr(uint256(priv_key_0));
    address acct_1 = cheats.addr(uint256(priv_key_1));
    address _challenger = address(0x6966904396bF2f8b173350bCcec5007A52669873);

    bytes header = hex"0e75f28b7a90f89995e522d0cd3a340345e60e249099d4cd96daef320a3abfc31df7f4c8f6f8bc5dc1de03f56202933ec2cc40acad1199f40c7b42aefd45bfb10000000800000002000000020000014000000000000000000000000000000000000000002b4982b07d4e522c2a94b3e7c5ab68bfeecc33c5fa355bc968491c62c12cf93f0cd04099c3d9742620bf0898cf3843116efc02e6f7d408ba443aa472f950e4f3";

    address initialOwner = address(this);

    struct NonSignerPK {
        uint256 x;
        uint256 y;
        uint32 stakeIndex;
    }

    struct RegistrantAPKG2 {
        uint256 apk0;
        uint256 apk1;
        uint256 apk2;
        uint256 apk3;
    }

    struct RegistrantAPKG1 {
        uint256 apk0;
        uint256 apk1;
    }

    struct SignerAggSig{
        uint256 sigma0;
        uint256 sigma1;
    }

    modifier cannotReinit() {
        cheats.expectRevert(bytes("Initializable: contract is already initialized"));
        _;
    }

    modifier fuzzedAddress(address addr) {
        cheats.assume(addr != address(0));
        cheats.assume(addr != address(eigenLayrProxyAdmin));
        cheats.assume(addr != address(dataLayrProxyAdmin));
        cheats.assume(addr != address(investmentManager));
        cheats.assume(addr != dlsm.owner());
        _;
    }

    modifier fuzzedOperatorIndex(uint8 operatorIndex) {
        cheats.assume(operatorIndex < getNumOperators());
        _;
    }

    //performs basic deployment before each test
    function setUp() public {
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

        // deploy all the DataLayr contracts
        _deployDataLayrContracts();

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

        //ensuring that the address of eigenpodmanager doesn't change
        bytes memory code = address(eigenPodManager).code;
        vm.etch(podManagerAddress, code);


        eigenPodManager = IEigenPodManager(podManagerAddress);



        ephemeralKeyHashes.push(0x3f9554986ff07e7ac0ca5d6e2094788cedcbbe5b9398dec9b124b28d0edca976);
        ephemeralKeyHashes.push(0x1f9554986ff07e7ac0ca5d6e2094788cedcbbe5b9398dec9b124b28d0edca976);
        ephemeralKeyHashes.push(0x3e9554986ff07e7ac0ca5d6e2094788cedcbbe5b9398dec9b124b28d0edca976);
        ephemeralKeyHashes.push(0x4f9554986ff07e7ac0ca5d6e2094788cedcbbe5b9398dec9b124b28d0edca976);
        ephemeralKeyHashes.push(0x5c9554986ff07e7ac0ca5d6e2094788cedcbbe5b9398dec9b124b28d0edca976);
        ephemeralKeyHashes.push(0x6c9554986ff07e7ac0ca5d6e2094788cedcbbe5b9398dec9b124b28d0edca976);
        ephemeralKeyHashes.push(0x2a9554986ff07e7ac0ca5d6e2094788cedcbbe5b9398dec9b124b28d0edca976);
        ephemeralKeyHashes.push(0x2b9554986ff07e7ac0ca5d6e2094788cedcbbe5b9398dec9b124b28d0edca976);
        ephemeralKeyHashes.push(0x1c9554986ff07e7ac0ca5d6e2094788cedcbbe5b9398dec9b124b28d0edca976);
        ephemeralKeyHashes.push(0xad9554986ff07e7ac0ca5d6e2094788cedcbbe5b9398dec9b124b28d0edca976);
        ephemeralKeyHashes.push(0xde9554986ff07e7ac0ca5d6e2094788cedcbbe5b9398dec9b124b28d0edca976);
        ephemeralKeyHashes.push(0xff9554986ff07e7ac0ca5d6e2094788cedcbbe5b9398dec9b124b28d0edca976);
        ephemeralKeyHashes.push(0xea9554986ff07e7ac0ca5d6e2094788cedcbbe5b9398dec9b124b28d0edca976);
        ephemeralKeyHashes.push(0x2a9554986ff07e7ac0ca5d6e2094788cedcbbe5b9398dec9b124b28d0edca976);
        ephemeralKeyHashes.push(0x3f9554986ff07e7ac0ca5d6e2094788cedcbbe5b9398dec9b124b28d0edca976);
    }

    // deploy all the DataLayr contracts. Relies on many EL contracts having already been deployed.
    function _deployDataLayrContracts() internal {
        // deploy proxy admin for ability to upgrade proxy contracts
        dataLayrProxyAdmin = new ProxyAdmin();

        // deploy pauser registry
        dataLayrPauserReg = new PauserRegistry(pauser, unpauser);

        // hard-coded inputs
        uint256 feePerBytePerTime = 1;
        uint256 _paymentFraudproofCollateral = 1e16;

        /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        challengeUtils = DataLayrChallengeUtils(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(dataLayrProxyAdmin), ""))
        );
        dlsm = DataLayrServiceManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(dataLayrProxyAdmin), ""))
        );
        ephemeralKeyRegistry = EphemeralKeyRegistry(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(dataLayrProxyAdmin), ""))
        );
        pubkeyCompendium = BLSPublicKeyCompendium(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(dataLayrProxyAdmin), ""))
        );
        dataLayrPaymentManager = DataLayrPaymentManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(dataLayrProxyAdmin), ""))
        );
        dlldc = DataLayrLowDegreeChallenge(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(dataLayrProxyAdmin), ""))
        );
        dlReg = BLSRegistryWithBomb(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(dataLayrProxyAdmin), ""))
        );

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        challengeUtilsImplementation = new DataLayrChallengeUtils();
        dlsmImplementation = new DataLayrServiceManager(
            dlReg,
            investmentManager,
            delegation,
            weth,
            dlldc,
            // TODO: fix this
            DataLayrBombVerifier(address(0)),
            ephemeralKeyRegistry,
            dataLayrPaymentManager
        );
        ephemeralKeyRegistryImplementation = new EphemeralKeyRegistry(dlReg, dlsm);
        pubkeyCompendiumImplementation = new BLSPublicKeyCompendium();
        dataLayrPaymentManagerImplementation = new DataLayrPaymentManager(
            delegation,
            dlsm,
            dlReg,
            weth,
            weth,
            // TODO: given that this address is the same as above in what we're deploying, we may want to eliminate the corresponding storage slot form the contract
            dlReg
        );
        dlldcImplementation = new DataLayrLowDegreeChallenge(dlsm, dlReg, challengeUtils);
        {
            uint32 _UNBONDING_PERIOD = uint32(14 days);
            uint8 _NUMBER_OF_QUORUMS = 2;
            dlRegImplementation = new BLSRegistryWithBomb(
                delegation,
                investmentManager,
                dlsm,
                _NUMBER_OF_QUORUMS,
                _UNBONDING_PERIOD,
                pubkeyCompendium,
                ephemeralKeyRegistry
            );
        }

        // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
        dataLayrProxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(challengeUtils))),
            address(challengeUtilsImplementation)
        );
        {
            uint16 quorumThresholdBasisPoints = 9000;
            uint16 adversaryThresholdBasisPoints = 4000;
            dataLayrProxyAdmin.upgradeAndCall(
                TransparentUpgradeableProxy(payable(address(dlsm))),
                address(dlsmImplementation),
                abi.encodeWithSelector(
                    DataLayrServiceManager.initialize.selector,
                    dataLayrPauserReg,
                    initialOwner,
                    quorumThresholdBasisPoints,
                    adversaryThresholdBasisPoints,
                    feePerBytePerTime
                )
            );
        }
        dataLayrProxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(ephemeralKeyRegistry))),
            address(ephemeralKeyRegistryImplementation)
        );
        dataLayrProxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(pubkeyCompendium))),
            address(pubkeyCompendiumImplementation)
        );
        dataLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(dataLayrPaymentManager))),
            address(dataLayrPaymentManagerImplementation),
            abi.encodeWithSelector(PaymentManager.initialize.selector, dataLayrPauserReg, _paymentFraudproofCollateral)
        );
        dataLayrProxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(dlldc))),
            address(dlldcImplementation)
        );
        {
            uint96 multiplier = 1e18;
            uint8 _NUMBER_OF_QUORUMS = 2;
            uint256[] memory _quorumBips = new uint256[](_NUMBER_OF_QUORUMS);
            // split 60% ETH quorum, 40% EIGEN quorum
            _quorumBips[0] = 6000;
            _quorumBips[1] = 4000;
            VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[] memory ethStratsAndMultipliers =
                new VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[](1);
            ethStratsAndMultipliers[0].strategy = wethStrat;
            ethStratsAndMultipliers[0].multiplier = multiplier;
            VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[] memory eigenStratsAndMultipliers =
                new VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[](1);
            eigenStratsAndMultipliers[0].strategy = eigenStrat;
            eigenStratsAndMultipliers[0].multiplier = multiplier;

            dataLayrProxyAdmin.upgradeAndCall(
                TransparentUpgradeableProxy(payable(address(dlReg))),
                address(dlRegImplementation),
                abi.encodeWithSelector(BLSRegistry.initialize.selector, _quorumBips, ethStratsAndMultipliers, eigenStratsAndMultipliers)
            );
        }
    }

    function calculateFee(uint256 totalBytes, uint256 feePerBytePerTime, uint256 duration)
        internal
        pure
        returns (uint256)
    {
        return uint256(totalBytes * feePerBytePerTime * duration * DURATION_SCALE);
    }

    function testDeploymentSuccessful() public {
        // assertTrue(address(eigen) != address(0), "eigen failed to deploy");
        assertTrue(address(eigenToken) != address(0), "eigenToken failed to deploy");
        assertTrue(address(delegation) != address(0), "delegation failed to deploy");
        assertTrue(address(investmentManager) != address(0), "investmentManager failed to deploy");
        assertTrue(address(slasher) != address(0), "slasher failed to deploy");
        assertTrue(address(weth) != address(0), "weth failed to deploy");
        assertTrue(address(dlsm) != address(0), "dlsm failed to deploy");
        assertTrue(address(dlReg) != address(0), "dlReg failed to deploy");
    }

    function testSig() public view {
        uint256[12] memory input;
        //1d9b51a4ffb5b3f402748854ea5bbb8025324782062324e99bedcdc2cec4102f
        //000000000004
        //00000918
        //00000007
        //00000000
        //00000003
        //0d8c5e0a5954cbbc30123d0990c7643b1e8b43278457d3a89de59cfc620ac48a
        //068a2ec2615a4064fd820f759d6030475fed69925655aae8a463e72b53f697e9
        //014d5b9af4f3e72635652fe695fdb3c46ee3e5142820b228bf9564fdef30bd92
        //0238c50db7b36820321b2e25700486c18e5750dea646d266870ec1be812456fa
        //1e041e0df4821a4b7668999e4381cca9c015916f033512ca0829179c639f285c
        //1a2ebe9095bed1d16f938c00d283c3a08462c7dc168a590ffa8ce192e05996ab

        (input[0], input[1]) = BLS.hashToG1(0x1d9b51a4ffb5b3f402748854ea5bbb8025324782062324e99bedcdc2cec4102f);
        input[3] = uint256(0x0d8c5e0a5954cbbc30123d0990c7643b1e8b43278457d3a89de59cfc620ac48a);
        input[2] = uint256(0x068a2ec2615a4064fd820f759d6030475fed69925655aae8a463e72b53f697e9);
        input[5] = uint256(0x014d5b9af4f3e72635652fe695fdb3c46ee3e5142820b228bf9564fdef30bd92);
        input[4] = uint256(0x0238c50db7b36820321b2e25700486c18e5750dea646d266870ec1be812456fa);
        input[6] = uint256(0x1e041e0df4821a4b7668999e4381cca9c015916f033512ca0829179c639f285c);
        input[7] = uint256(0x1a2ebe9095bed1d16f938c00d283c3a08462c7dc168a590ffa8ce192e05996ab);
        // insert negated coordinates of the generator for G2
        input[8] = BLS.nG2x1;
        input[9] = BLS.nG2x0;
        input[10] = BLS.nG2y1;
        input[11] = BLS.nG2y0;

        assembly {
            // check the pairing; if incorrect, revert
            if iszero(
                // staticcall address 8 (ecPairing precompile), forward all gas, send 384 bytes (0x180 in hex) = 12 (32-byte) inputs.
                // store the return data in input[11] (352 bytes / '0x160' in hex), and copy only 32 bytes of return data (since precompile returns boolean)
                staticcall(not(0), 0x08, input, 0x180, add(input, 0x160), 0x20)
            ) { revert(0, 0) }
        }

        // check that the provided signature is correct
        require(input[11] == 1, "BLSSignatureChecker.checkSignatures: Pairing unsuccessful");

        // abi.encodePacked(
        //     keccak256(
        //         abi.encodePacked(searchData.metadata.globalDataStoreId, searchData.metadata.headerHash, searchData.duration, initTime, searchData.index)
        //     ),
        //     uint48(dlReg.getLengthOfTotalStakeHistory() - 1),
        //     searchData.metadata.referenceBlockNumber,
        //     searchData.metadata.globalDataStoreId,
        //     numberOfNonSigners,
        //     // no pubkeys here since zero nonSigners for now
        //     uint32(dlReg.getApkUpdatesLength() - 1),
        //     apk_0,
        //     apk_1,
        //     apk_2,
        //     apk_3,
        //     sigma_0,
        //     sigma_1
        // );
    }

    function testBLSPairing() public {
            uint256[12] memory input;

            uint256 sigmaX = 18033935401377046968253993369420882761639101147199761382164100964672839397476;
            uint256 sigmaY = 1296611607075364961854999662642612779184492063389140410860059877500726169961;

            bytes32 msgHash = 0x536ea2113b06bc65d2d6310b51424f268f1b3155e1fe82cbc90d9b8712d14a0a;
            (uint256 msgHashX, uint256 msgHashY) = BLS.hashToG1(msgHash);

            emit log_named_uint("msgHashX", msgHashX);
            emit log_named_uint("msgHashY", msgHashY);

            input[0] = sigmaX;
            input[1] = sigmaY;
            input[2] = BLS.nG2x1;
            input[3] = BLS.nG2x0;
            input[4] = BLS.nG2y1;
            input[5] = BLS.nG2y0;

            input[6] = msgHashX;
            input[7] = msgHashY;
            // insert negated coordinates of the generator for G2
            input[8] = 2548741418739206695596229529236657819733103689248810431091319058064536250278;
            input[9] = 17890127137359027111482509378509337249586291091685072336190236845225812702820;
            input[10] = 12498134380415317036640719391312524222291167329168408451224344109201613968031;
            input[11] = 18577908915005185161399472001797886901908616360139528062172259974922524099491;

            assembly {
                // check the pairing; if incorrect, revert
                if iszero(
                    staticcall(sub(gas(), 2000), 8, input, 0x180, input, 0x20)
                ) {
                    revert(0, 0)
                }
            }

            require(
                input[0] == 1,
                "BLSSignatureChecker.checkSignatures: Pairing unsuccessful"
            );
        }

    function testVKPairing() public {
        uint256[12] memory input;

        uint256 pkg1X = 11746114415387181186350609321861313487282937637157292915572974055983718048797;
        uint256 pkg1Y = 6199836912972052411871307285755230980030751238632264470990041456311661808876;


        input[0] = pkg1X;
        input[1] = pkg1Y;
        input[2] = BLS.nG2x1;
        input[3] = BLS.nG2x0;
        input[4] = BLS.nG2y1;
        input[5] = BLS.nG2y0;
        
        input[6] = 1;
        input[7] = 2;
        // insert negated coordinates of the generator for G2
        input[8] = 2548741418739206695596229529236657819733103689248810431091319058064536250278;
        input[9] = 17890127137359027111482509378509337249586291091685072336190236845225812702820;
        input[10] = 12498134380415317036640719391312524222291167329168408451224344109201613968031;
        input[11] = 18577908915005185161399472001797886901908616360139528062172259974922524099491;

        assembly {
            // check the pairing; if incorrect, revert
            if iszero(
                staticcall(sub(gas(), 2000), 8, input, 0x180, input, 0x20)
            ) { revert(0, 0) }
        }

        require(input[0] == 1, "BLSSignatureChecker.checkSignatures: Pairing unsuccessful");

    }
}
