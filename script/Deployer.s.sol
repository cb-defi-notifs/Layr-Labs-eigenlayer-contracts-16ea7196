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

import "../src/contracts/core/InvestmentManager.sol";
import "../src/contracts/strategies/InvestmentStrategyBase.sol";
import "../src/contracts/core/Slasher.sol";

import "../src/contracts/pods/EigenPod.sol";
import "../src/contracts/pods/EigenPodManager.sol";

import "../src/contracts/permissions/PauserRegistry.sol";
import "../src/contracts/middleware/BLSPublicKeyCompendium.sol";

import "../src/contracts/libraries/BytesLib.sol";

import "../src/test/mocks/EmptyContract.sol";
import "../src/test/mocks/BeaconChainOracleMock.sol";
import "../src/test/mocks/ETHDepositMock.sol";

import "forge-std/Test.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import "../src/contracts/libraries/BytesLib.sol";

// # To load the variables in the .env file
// source .env

// # To deploy and verify our contract
// forge script script/Deployer.s.sol:EigenLayrDeployer --rpc-url $RPC_URL  --private-key $PRIVATE_KEY --broadcast -vvvv
contract EigenLayrDeployer is Script, DSTest {
    //,
    // Signers,
    // SignatureUtils

    using BytesLib for bytes;

    Vm cheats = Vm(HEVM_ADDRESS);

    uint256 public constant DURATION_SCALE = 1 hours;

    // EigenLayer contracts
    ProxyAdmin public eigenLayrProxyAdmin;
    PauserRegistry public eigenLayrPauserReg;
    Slasher public slasher;
    EigenLayrDelegation public delegation;
    EigenPodManager public eigenPodManager;
    InvestmentManager public investmentManager;
    IEigenPod public pod;
    IETHPOSDeposit public ethPOSDeposit;
    IBeacon public eigenPodBeacon;
    IBeaconChainOracle public beaconChainOracle;

    // DataLayr contracts
    ProxyAdmin public dataLayrProxyAdmin;
    PauserRegistry public dataLayrPauserReg;

    // testing/mock contracts
    IERC20 public eigenToken;
    IERC20 public weth;
    InvestmentStrategyBase public wethStrat;
    InvestmentStrategyBase public eigenStrat;
    InvestmentStrategyBase public baseStrategyImplementation;
    EmptyContract public emptyContract;

    uint256 nonce = 69;
    uint32 PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD = 7 days / 12 seconds;
    uint256 REQUIRED_BALANCE_WEI = 31.4 ether;
    uint64 MAX_PARTIAL_WTIHDRAWAL_AMOUNT_GWEI = 1 ether / 1e9;

    bytes[] registrationData;

    //strategy indexes for undelegation (see commitUndelegation function)
    uint256[] public strategyIndexes;

    uint256 wethInitialSupply = 10e50;
    address storer = address(420);
    address registrant = address(0x4206904396bF2f8b173350ADdEc5007A52664293); //sk: e88d9d864d5d731226020c5d2f02b62a4ce2a4534a39c225d32d3db795f83319

    //from testing seed phrase
    // bytes32 priv_key_0 =
    //     0x1234567812345678123456781234567812345678123456781234567812345678;
    // address acct_0 = cheats.addr(uint256(priv_key_0));

    // bytes32 priv_key_1 =
    //     0x1234567812345678123456781234567812345698123456781234567812348976;
    // address acct_1 = cheats.addr(uint256(priv_key_1));

    uint256 public constant eigenTotalSupply = 1000e18;

    uint256 public gasLimit = 750000;

    function run() external {
        vm.startBroadcast();

        emit log_address(address(this));
        address pauser = msg.sender;
        address unpauser = msg.sender;
        address eigenLayrReputedMultisig = msg.sender;




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
        pod = new EigenPod(ethPOSDeposit, PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD, REQUIRED_BALANCE_WEI, MAX_PARTIAL_WTIHDRAWAL_AMOUNT_GWEI);

        eigenPodBeacon = new UpgradeableBeacon(address(pod));

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        EigenLayrDelegation delegationImplementation = new EigenLayrDelegation(investmentManager, slasher);
        InvestmentManager investmentManagerImplementation = new InvestmentManager(delegation, eigenPodManager, slasher);
        Slasher slasherImplementation = new Slasher(investmentManager, delegation);
        EigenPodManager eigenPodManagerImplementation = new EigenPodManager(ethPOSDeposit, eigenPodBeacon, investmentManager, slasher);

        // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(delegation))),
            address(delegationImplementation),
            abi.encodeWithSelector(EigenLayrDelegation.initialize.selector, eigenLayrPauserReg, eigenLayrReputedMultisig)
        );
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(investmentManager))),
            address(investmentManagerImplementation),
            abi.encodeWithSelector(InvestmentManager.initialize.selector, eigenLayrPauserReg, eigenLayrReputedMultisig)
        );
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(slasher))),
            address(slasherImplementation),
            abi.encodeWithSelector(Slasher.initialize.selector, eigenLayrPauserReg, eigenLayrReputedMultisig)
        );
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(eigenPodManager))),
            address(eigenPodManagerImplementation),
            abi.encodeWithSelector(EigenPodManager.initialize.selector, beaconChainOracle, eigenLayrReputedMultisig)
        );


        //simple ERC20 (**NOT** WETH-like!), used in a test investment strategy
        weth = new ERC20PresetFixedSupply(
            "weth",
            "WETH",
            wethInitialSupply,
            msg.sender
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
            msg.sender
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

        verifyContract(delegationImplementation, investmentManagerImplementation, slasherImplementation, eigenPodManagerImplementation);
        verifyContract(delegation, investmentManager, slasher, eigenPodManager);
        verifyOwners(eigenLayrReputedMultisig);
        checkPauserInitializations(pauser, unpauser);
        
        vm.writeFile("data/investmentManager.addr", vm.toString(address(investmentManager)));
        vm.writeFile("data/delegation.addr", vm.toString(address(delegation)));
        vm.writeFile("data/slasher.addr", vm.toString(address(slasher)));
        vm.writeFile("data/weth.addr", vm.toString(address(weth)));
        vm.writeFile("data/wethStrat.addr", vm.toString(address(wethStrat)));
        vm.writeFile("data/eigen.addr", vm.toString(address(eigenToken)));
        vm.writeFile("data/eigenStrat.addr", vm.toString(address(eigenStrat)));
        vm.writeFile("data/eigenStrat.addr", vm.toString(address(eigenStrat)));

        vm.stopBroadcast();
    }

    function verifyContract(
        EigenLayrDelegation delegationContract,  
        InvestmentManager investmentManagerContract, 
        Slasher slasherContract,  
        EigenPodManager eigenPodManagerContract
    ) internal view {
        require(address(delegationContract.slasher()) == address(slasher), "delegation slasher address not set correctly");
        require(address(delegationContract.investmentManager()) == address(slasher), "delegation investmentManager address not set correctly");

        require(address(investmentManagerContract.slasher()) == address(slasher), "investmentManager slasher address not set correctly");
        require(address(investmentManagerContract.delegation()) == address(delegation), "investmentManager delegation address not set correctly");
        require(address(investmentManagerContract.eigenPodManager()) == address(eigenPodManager), "investmentManager eigenPodManager address not set correctly");

        require(address(slasherContract.investmentManager()) == address(investmentManager), "slasher's investmentManager not set correctly");
        require(address(slasherContract.delegation()) == address(delegation), "slasher's delegation not set correctly");

        require(address(eigenPodManagerContract.ethPOS()) == address(ethPOSDeposit), " eigenPodManagerethPOSDeposit contract address not set correctly");
        require(address(eigenPodManagerContract.eigenPodBeacon()) == address(eigenPodBeacon), "eigenPodManager eigenPodBeacon contract address not set correctly");
        require(address(eigenPodManagerContract.investmentManager()) == address(investmentManager), "eigenPodManager investmentManager contract address not set correctly");
        require(address(eigenPodManagerContract.slasher()) == address(slasher), "eigenPodManager slasher contract address not set correctly");

    }

    function verifyOwners(
        address eigenLayrReputedMultisig  
    )internal view {
       
        require(investmentManager.owner() == eigenLayrReputedMultisig, "investmentManager owner not set correctly");
        require(delegation.owner() == eigenLayrReputedMultisig, "delegation owner not set correctly");
        require(slasher.owner() == eigenLayrReputedMultisig, "slasher owner not set correctly");
        require(eigenPodManager.owner() == eigenLayrReputedMultisig, "delegation owner not set correctly");

    }
    function checkPauserInitializations(
        address pauser,
        address unpauser
    ) internal view {
        require(address(delegation.pauserRegistry()) == address(eigenLayrPauserReg), "delegation's pauser registry not set correctly");
        require(address(investmentManager.pauserRegistry()) == address(eigenLayrPauserReg), "investmentManager's pauser registry not set correctly");
        require(address(slasher.pauserRegistry()) == address(eigenLayrPauserReg), "slasher's pauser registry not set correctly");

        require(eigenLayrPauserReg.pauser() == pauser, "pauser not set correctly");
        require(eigenLayrPauserReg.unpauser() == unpauser, "pauser not set correctly");
    }
}



    

