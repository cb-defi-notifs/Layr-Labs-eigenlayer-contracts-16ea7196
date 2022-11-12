// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "../src/contracts/interfaces/IEigenLayrDelegation.sol";
import "../src/contracts/core/EigenLayrDelegation.sol";

import "../src/contracts/interfaces/IETHPOSDeposit.sol";
import "../src/contracts/interfaces/IBeaconChainOracle.sol";

import "../src/contracts/investment/InvestmentManager.sol";
import "../src/contracts/investment/InvestmentStrategyBase.sol";
import "../src/contracts/investment/Slasher.sol";

import "../src/contracts/pods/EigenPod.sol";
import "../src/contracts/pods/EigenPodManager.sol";

import "../src/contracts/permissions/PauserRegistry.sol";
import "../src/contracts/middleware/DataLayr/DataLayrServiceManager.sol";
import "../src/contracts/middleware/BLSRegistryWithBomb.sol";
import "../src/contracts/middleware/BLSPublicKeyCompendium.sol";
import "../src/contracts/middleware/DataLayr/DataLayrPaymentManager.sol";
import "../src/contracts/middleware/EphemeralKeyRegistry.sol";
import "../src/contracts/middleware/DataLayr/DataLayrChallengeUtils.sol";
import "../src/contracts/middleware/DataLayr/DataLayrLowDegreeChallenge.sol";

import "../src/contracts/libraries/BLS.sol";
import "../src/contracts/libraries/BytesLib.sol";
import "../src/contracts/libraries/DataStoreUtils.sol";

import "../src/test/utils/Signers.sol";
import "../src/test/utils/SignatureUtils.sol";

import "../src/test/mocks/EmptyContract.sol";
import "../src/test/mocks/BeaconChainOracleMock.sol";
import "../src/test/mocks/ETHDepositMock.sol";

import "forge-std/Test.sol";




import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import "../src/contracts/utils/ERC165_Universal.sol";
import "../src/contracts/utils/ERC1155TokenReceiver.sol";
import "../src/contracts/libraries/BLS.sol";
import "../src/contracts/libraries/BytesLib.sol";
import "../src/contracts/libraries/DataStoreUtils.sol";

// # To load the variables in the .env file
// source .env

// # To deploy and verify our contract
// forge script script/Deployer.s.sol:EigenLayrDeployer --rpc-url $RPC_URL  --private-key $PRIVATE_KEY --broadcast -vvvv

//TODO: encode data properly so that we initialize TransparentUpgradeableProxy contracts in their constructor rather than a separate call (if possible)
contract EigenLayrDeployer is Script, DSTest, ERC165_Universal, ERC1155TokenReceiver {
    //,
    // Signers,
    // SignatureUtils

    using BytesLib for bytes;

    // Eigen public eigen;
    IERC20 public eigen;

    uint256 public constant DURATION_SCALE = 1 hours;
    Vm cheats = Vm(HEVM_ADDRESS);
    IERC20 public eigenToken;
    InvestmentStrategyBase public eigenStrat;
    EigenLayrDelegation public delegation;
    InvestmentManager public investmentManager;
    EigenPodManager public eigenPodManager;
    Slasher public slasher;
    PauserRegistry public pauserReg;
    IERC20 public weth;

    InvestmentStrategyBase public wethStrat;
    ProxyAdmin public eigenLayrProxyAdmin;
    DataLayrPaymentManager public dataLayrPaymentManager;
    InvestmentStrategyBase public liquidStakingMockStrat;
    InvestmentStrategyBase public baseStrategyImplementation;

    DataLayrServiceManager public dlsm;
    DataLayrLowDegreeChallenge public dlldc;
    DataLayrChallengeUtils public challengeUtils;
    BLSRegistryWithBomb public dlReg;
    BLSPublicKeyCompendium public pubkeyCompendium;
    EphemeralKeyRegistry public ephemeralKeyRegistry;

    DataLayrChallengeUtils public challengeUtilsImplementation;
    DataLayrServiceManager public dlsmImplementation;
    EphemeralKeyRegistry public ephemeralKeyRegistryImplementation;
    BLSPublicKeyCompendium public pubkeyCompendiumImplementation;
    DataLayrPaymentManager public dataLayrPaymentManagerImplementation;
    DataLayrLowDegreeChallenge public dlldcImplementation;
    BLSRegistryWithBomb public dlRegImplementation;

    EmptyContract public emptyContract;

    address initialOwner = address(this);

    IEigenPod public pod;
    IETHPOSDeposit public ethPOSDeposit;
    IBeacon public eigenPodBeacon;
    IBeaconChainOracle public beaconChainOracle;

    // ERC20PresetFixedSupply public liquidStakingMockToken;
    // InvestmentStrategyBase public liquidStakingMockStrat;

    uint256 nonce = 69;

    bytes[] registrationData;

    // strategy index => IInvestmentStrategy
    mapping(uint256 => IInvestmentStrategy) public strategies;
    // number of strategies deployed
    uint256 public numberOfStrats;

    //strategy indexes for undelegation (see commitUndelegation function)
    uint256[] public strategyIndexes;

    uint256 wethInitialSupply = 10e50;
    uint256 undelegationFraudProofInterval = 7 days;
    address storer = address(420);
    address registrant = address(0x4206904396bF2f8b173350ADdEc5007A52664293); //sk: e88d9d864d5d731226020c5d2f02b62a4ce2a4534a39c225d32d3db795f83319

    //from testing seed phrase
    // bytes32 priv_key_0 =
    //     0x1234567812345678123456781234567812345678123456781234567812345678;
    // address acct_0 = cheats.addr(uint256(priv_key_0));

    // bytes32 priv_key_1 =
    //     0x1234567812345678123456781234567812345698123456781234567812348976;
    // address acct_1 = cheats.addr(uint256(priv_key_1));

    bytes32 public ephemeralKey = 0x3290567812345678123456781234577812345698123456781234567812344389;

    uint256 public constant eigenTotalSupply = 1000e18;

    uint256 public gasLimit = 750000;

    function run() external {
        vm.startBroadcast();

        emit log_address(address(this));
        // deploy proxy admin for ability to upgrade proxy contracts
        eigenLayrProxyAdmin = new ProxyAdmin();

        pauserReg = new PauserRegistry(msg.sender, msg.sender);

        //TODO: handle pod manager correctly
        eigenPodManager = EigenPodManager(address(0));

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
            abi.encodeWithSelector(EigenLayrDelegation.initialize.selector, pauserReg, initialOwner)
        );
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(investmentManager))),
            address(investmentManagerImplementation),
            abi.encodeWithSelector(InvestmentManager.initialize.selector, pauserReg, initialOwner)
        );
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(slasher))),
            address(slasherImplementation),
            abi.encodeWithSelector(Slasher.initialize.selector, pauserReg, initialOwner)
        );
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(eigenPodManager))),
            address(eigenPodManagerImplementation),
            abi.encodeWithSelector(EigenPodManager.initialize.selector, beaconChainOracle)
        );

        vm.writeFile("data/investmentManager.addr", vm.toString(address(investmentManager)));
        vm.writeFile("data/delegation.addr", vm.toString(address(delegation)));

        //simple ERC20 (*NOT WETH-like!), used in a test investment strategy
        weth = new ERC20PresetFixedSupply(
            "weth",
            "WETH",
            wethInitialSupply,
            msg.sender
        );

        vm.writeFile("data/weth.addr", vm.toString(address(weth)));

        baseStrategyImplementation = new InvestmentStrategyBase(investmentManager);

        // deploy InvestmentStrategyBase contract implementation, then create upgradeable proxy that points to implementation
        // initialize InvestmentStrategyBase proxy
        wethStrat = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(baseStrategyImplementation),
                    address(eigenLayrProxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, weth, pauserReg)
                )
            )
        );
        vm.writeFile("data/wethStrat.addr", vm.toString(address(wethStrat)));

        eigen = new ERC20PresetFixedSupply(
            "eigen",
            "EIGEN",
            wethInitialSupply,
            msg.sender
        );

        vm.writeFile("data/eigen.addr", vm.toString(address(eigen)));

        // deploy InvestmentStrategyBase contract implementation, then create upgradeable proxy that points to implementation
        // initialize InvestmentStrategyBase proxy
        eigenStrat = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(baseStrategyImplementation),
                    address(eigenLayrProxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, eigen, pauserReg)
                )
            )
        );

        vm.writeFile("data/eigenStrat.addr", vm.toString(address(eigenStrat)));

        // deploy all the DataLayr contracts
        _deployDataLayrContracts();

        vm.stopBroadcast();
    }

    // deploy all the DataLayr contracts. Relies on many EL contracts having already been deployed.
    function _deployDataLayrContracts() internal {
        // hard-coded inputs
        uint256 feePerBytePerTime = 1;
        uint256 _paymentFraudproofCollateral = 1e16;

        /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        challengeUtils = DataLayrChallengeUtils(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );
        dlsm = DataLayrServiceManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );
        ephemeralKeyRegistry = EphemeralKeyRegistry(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );
        pubkeyCompendium = BLSPublicKeyCompendium(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );
        dataLayrPaymentManager = DataLayrPaymentManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );
        dlldc = DataLayrLowDegreeChallenge(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );
        dlReg = BLSRegistryWithBomb(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
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
            // pauserReg,
            // feePerBytePerTime
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
        eigenLayrProxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(challengeUtils))),
            address(challengeUtilsImplementation)
        );
        {
            uint16 quorumThresholdBasisPoints = 9000;
            uint16 adversaryThresholdBasisPoints = 4000;
            eigenLayrProxyAdmin.upgradeAndCall(
                TransparentUpgradeableProxy(payable(address(dlsm))),
                address(dlsmImplementation),
                abi.encodeWithSelector(
                    DataLayrServiceManager.initialize.selector,
                    pauserReg,
                    initialOwner,
                    quorumThresholdBasisPoints,
                    adversaryThresholdBasisPoints,
                    feePerBytePerTime
                )
            );
        }
        eigenLayrProxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(ephemeralKeyRegistry))),
            address(ephemeralKeyRegistryImplementation)
        );
        eigenLayrProxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(pubkeyCompendium))),
            address(pubkeyCompendiumImplementation)
        );
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(dataLayrPaymentManager))),
            address(dataLayrPaymentManagerImplementation),
            abi.encodeWithSelector(PaymentManager.initialize.selector, pauserReg, _paymentFraudproofCollateral)
        );
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(dlldc))),
            address(dlldcImplementation),
            abi.encodeWithSelector(DataLayrLowDegreeChallenge.initialize.selector, gasLimit)
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

            eigenLayrProxyAdmin.upgradeAndCall(
                TransparentUpgradeableProxy(payable(address(dlReg))),
                address(dlRegImplementation),
                abi.encodeWithSelector(BLSRegistry.initialize.selector, _quorumBips, ethStratsAndMultipliers, eigenStratsAndMultipliers)
            );
        }

        vm.writeFile("data/dlsm.addr", vm.toString(address(dlsm)));
        vm.writeFile("data/dlReg.addr", vm.toString(address(dlReg)));
    }

    function numberFromAscII(bytes1 b) private pure returns (uint8 res) {
        if (b >= "0" && b <= "9") {
            return uint8(b) - uint8(bytes1("0"));
        } else if (b >= "A" && b <= "F") {
            return 10 + uint8(b) - uint8(bytes1("A"));
        } else if (b >= "a" && b <= "f") {
            return 10 + uint8(b) - uint8(bytes1("a"));
        }
        return uint8(b); // or return error ...
    }

    function convertString(string memory str) public pure returns (uint256 value) {
        bytes memory b = bytes(str);
        uint256 number = 0;
        for (uint256 i = 0; i < b.length; i++) {
            number = number << 4; // or number = number * 16
            number |= numberFromAscII(b[i]); // or number += numberFromAscII(b[i]);
        }
        return number;
    }
}
