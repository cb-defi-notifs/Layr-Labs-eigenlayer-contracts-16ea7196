// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../src/contracts/interfaces/IEigenLayrDelegation.sol";
import "../src/contracts/core/EigenLayrDelegation.sol";

import "../src/contracts/investment/InvestmentManager.sol";
import "../src/contracts/investment/InvestmentStrategyBase.sol";
import "../src/contracts/investment/Slasher.sol";

import "../src/contracts/middleware/Repository.sol";
import "../src/contracts/middleware/DataLayr/DataLayrServiceManager.sol";
import "../src/contracts/middleware/BLSRegistryWithBomb.sol";
import "../src/contracts/middleware/DataLayr/DataLayrPaymentManager.sol";
import "../src/contracts/middleware/EphemeralKeyRegistry.sol";
import "../src/contracts/middleware/DataLayr/DataLayrChallengeUtils.sol";
import "../src/contracts/middleware/DataLayr/DataLayrLowDegreeChallenge.sol";
import "../src/contracts/middleware/BLSPublicKeyCompendium.sol";

import "../src/contracts/permissions/PauserRegistry.sol";

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

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

    Vm cheats = Vm(HEVM_ADDRESS);

    uint256 public constant DURATION_SCALE = 1 hours;
    // Eigen public eigen;
    IERC20 public eigen;
    InvestmentStrategyBase public eigenStrat;
    EigenLayrDelegation public delegation;
    InvestmentManager public investmentManager;
    EphemeralKeyRegistry public ephemeralKeyRegistry;
    BLSPublicKeyCompendium public pubkeyCompendium;
    Slasher public slasher;
    BLSRegistryWithBomb public dlReg;
    DataLayrServiceManager public dlsm;
    DataLayrLowDegreeChallenge public dlldc;

    PauserRegistry public pauserReg;
    IERC20 public weth;
    InvestmentStrategyBase public wethStrat;
    InvestmentStrategyBase public baseStrategyImplementation;
    IRepository public dlRepository;

    ProxyAdmin public eigenLayrProxyAdmin;

    DataLayrPaymentManager public dataLayrPaymentManager;

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

    uint256 mainHonchoPrivKey = vm.envUint("PRIVATE_KEY_UINT");

    address mainHoncho = cheats.addr(mainHonchoPrivKey);

    //performs basic deployment before each test
    function run() external {
        vm.startBroadcast();
        address initialOwner = address(this);
        emit log_address(mainHoncho);
        emit log_address(address(this));
        // deploy proxy admin for ability to upgrade proxy contracts
        eigenLayrProxyAdmin = new ProxyAdmin();

        pauserReg = new PauserRegistry(msg.sender, msg.sender);

        // deploy delegation contract implementation, then create upgradeable proxy that points to implementation
        // can't initialize immediately since initializer depends on `investmentManager` address
        delegation = new EigenLayrDelegation();
        delegation = EigenLayrDelegation(
            address(
                new TransparentUpgradeableProxy(
                    address(delegation),
                    address(eigenLayrProxyAdmin),
                    ""
                )
            )
        );

        // deploy InvestmentManager contract implementation, then create upgradeable proxy that points to implementation
        // can't initialize immediately since initializer depends on `slasher` address
        investmentManager = new InvestmentManager(delegation);
        investmentManager = InvestmentManager(
            address(
                new TransparentUpgradeableProxy(
                    address(investmentManager),
                    address(eigenLayrProxyAdmin),
                    ""
                )
            )
        );

        vm.writeFile("data/investmentManager.addr", vm.toString(address(investmentManager)));

        // deploy slasher as upgradable proxy and initialize it
        Slasher slasherImplementation = new Slasher();
        slasher = Slasher(
            address(
                new TransparentUpgradeableProxy(
                    address(slasherImplementation),
                    address(eigenLayrProxyAdmin),
                    abi.encodeWithSelector(Slasher.initialize.selector, investmentManager, delegation, pauserReg, initialOwner)
                )
            )
        );

        // initialize the investmentManager (proxy) contract. This is possible now that `slasher` is deployed
        investmentManager.initialize(slasher, pauserReg, initialOwner);

        // initialize the delegation (proxy) contract. This is possible now that `investmentManager` is deployed
        delegation.initialize(investmentManager, pauserReg, initialOwner);
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
        // hard-coded input
        uint96 multiplier = 1e18;

        DataLayrChallengeUtils challengeUtils = new DataLayrChallengeUtils();

        dlRepository = new Repository(delegation, investmentManager);

        vm.writeFile("data/dlRepository.addr", vm.toString(address(dlRepository)));

        uint256 feePerBytePerTime = 1;
        dlsm = new DataLayrServiceManager(
            investmentManager,
            delegation,
            dlRepository,
            weth,
            pauserReg,
            feePerBytePerTime
        );

        vm.writeFile("data/dlsm.addr", vm.toString(address(dlsm)));

        uint32 unbondingPeriod = uint32(14 days);
        ephemeralKeyRegistry = new EphemeralKeyRegistry(dlRepository);

        // hard-coded inputs
        VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[] memory ethStratsAndMultipliers =
            new VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[](1);
        ethStratsAndMultipliers[0].strategy = wethStrat;
        ethStratsAndMultipliers[0].multiplier = multiplier;
        VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[] memory eigenStratsAndMultipliers =
            new VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[](1);
        eigenStratsAndMultipliers[0].strategy = eigenStrat;
        eigenStratsAndMultipliers[0].multiplier = multiplier;
        uint8 _NUMBER_OF_QUORUMS = 2;
        uint256[] memory _quorumBips = new uint256[](_NUMBER_OF_QUORUMS);
        // split 60% ETH quorum, 40% EIGEN quorum
        _quorumBips[0] = 6000;
        _quorumBips[1] = 4000;

        pubkeyCompendium = new BLSPublicKeyCompendium();

        dlReg = new BLSRegistryWithBomb(
            Repository(address(dlRepository)),
            delegation,
            investmentManager,
            ephemeralKeyRegistry,
            unbondingPeriod,
            _NUMBER_OF_QUORUMS,
            _quorumBips,
            ethStratsAndMultipliers,
            eigenStratsAndMultipliers,
            pubkeyCompendium
        );

        vm.writeFile("data/dlReg.addr", vm.toString(address(dlReg)));

        Repository(address(dlRepository)).initialize(dlReg, dlsm, dlReg, msg.sender);
        uint256 _paymentFraudproofCollateral = 1e16;

        dataLayrPaymentManager = new DataLayrPaymentManager(
            weth,
            _paymentFraudproofCollateral,
            dlRepository,
            dlsm,
            pauserReg
        );

        dlldc = new DataLayrLowDegreeChallenge(dlsm, dlReg, challengeUtils);

        dlsm.setLowDegreeChallenge(dlldc);
        dlsm.setPaymentManager(dataLayrPaymentManager);
        dlsm.setEphemeralKeyRegistry(ephemeralKeyRegistry);
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
