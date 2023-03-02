// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "../src/contracts/interfaces/IETHPOSDeposit.sol";
import "../src/contracts/interfaces/IBeaconChainOracle.sol";

import "../src/contracts/core/InvestmentManager.sol";
import "../src/contracts/core/Slasher.sol";
import "../src/contracts/core/EigenLayerDelegation.sol";

import "../src/contracts/strategies/InvestmentStrategyBase.sol";

import "../src/contracts/pods/EigenPod.sol";
import "../src/contracts/pods/EigenPodManager.sol";
import "../src/contracts/pods/EigenPodPaymentEscrow.sol";

import "../src/contracts/permissions/PauserRegistry.sol";
import "../src/contracts/middleware/BLSPublicKeyCompendium.sol";

import "../src/contracts/libraries/BytesLib.sol";

import "../src/test/mocks/EmptyContract.sol";
import "../src/test/mocks/ETHDepositMock.sol";
import "../src/test/utils/Owners.sol";

import "forge-std/Test.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import "../src/contracts/libraries/BytesLib.sol";

// # To load the variables in the .env file
// source .env

// # To deploy and verify our contract
// forge script script/Deployer.s.sol:EigenLayerDeployer --rpc-url $RPC_URL  --private-key $PRIVATE_KEY --broadcast -vvvv
contract EigenLayerDeployer is Script, Owners {
    using BytesLib for bytes;

    // EigenLayer Contracts
    ProxyAdmin public eigenLayerProxyAdmin;
    PauserRegistry public eigenLayerPauserReg;
    Slasher public slasher;
    Slasher public slasherImplementation;
    EigenLayerDelegation public delegation;
    EigenLayerDelegation public delegationImplementation;
    InvestmentManager public investmentManager;
    InvestmentManager public investmentManagerImplementation;
    EigenPodManager public eigenPodManager;
    EigenPodManager public eigenPodManagerImplementation;
    EigenPodPaymentEscrow public eigenPodPaymentEscrow;
    EigenPodPaymentEscrow public eigenPodPaymentEscrowImplementation;
    UpgradeableBeacon public eigenPodBeacon;
    EigenPod public eigenPodImplementation;

    EmptyContract public emptyContract;

    // TODO: set these addresses
    address eigenLayerReputedMultisig;
    address eigenLayerTeamMultisig;

    // TODO: set this correctly instead of using a mock (possibly dependent upon network)
    IETHPOSDeposit public ethPOSDeposit;

    // TODO: don't deploy these to mainnet
    // testing/mock contracts
    IERC20 public eigenToken;
    IERC20 public weth;
    InvestmentStrategyBase public wethStrat;
    InvestmentStrategyBase public eigenStrat;
    InvestmentStrategyBase public baseStrategyImplementation;
    uint256 wethInitialSupply = 10e50;

    // IMMUTABLES TO SET
    // one week in blocks
    uint32 PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS = 7 days / 12 seconds;
    uint256 REQUIRED_BALANCE_WEI = 31 ether;
    uint64 MAX_PARTIAL_WTIHDRAWAL_AMOUNT_GWEI = 1 ether / 1e9;

    // OTHER DEPLOYMENT PARAMETERS
    // pause *nothing*
    uint256 INVESTMENT_MANAGER_INIT_PAUSED_STATUS = 0;
    // pause *everything*
    uint256 SLASHER_INIT_PAUSED_STATUS = type(uint256).max;
    // pause *everything*
    uint256 DELEGATION_INIT_PAUSED_STATUS = type(uint256).max;
    // pause *all of the proof-related functionality* (everything that can be paused other than creation of EigenPods)
    uint256 EIGENPOD_MANAGER_INIT_PAUSED_STATUS = (2**1) + (2**2) + (2**3) + (2**4);
    // pause *nothing*
    uint256 EIGENPOD_PAYMENT_ESCROW_INIT_PAUSED_STATUS = 0;
    // one week in blocks
    uint32 INIT_ESCROW_DELAY_BLOCKS = 7 days / 12 seconds;

    function run() external {
        vm.startBroadcast();        

        // deploy proxy admin for ability to upgrade proxy contracts
        eigenLayerProxyAdmin = new ProxyAdmin();

        eigenLayerProxyAdmin.transferOwnership(eigenLayerReputedMultisig);

        //deploy pauser registry
        eigenLayerPauserReg = new PauserRegistry(address(eigenLayerTeamMultisig), eigenLayerReputedMultisig);

        /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        emptyContract = new EmptyContract();
        delegation = EigenLayerDelegation(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );
        investmentManager = InvestmentManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );
        slasher = Slasher(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );
        eigenPodManager = EigenPodManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );
        eigenPodPaymentEscrow = EigenPodPaymentEscrow(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );

        ethPOSDeposit = new ETHPOSDepositMock();
        eigenPodImplementation = new EigenPod(
            ethPOSDeposit,
            eigenPodPaymentEscrow,
            PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS,
            REQUIRED_BALANCE_WEI,
            MAX_PARTIAL_WTIHDRAWAL_AMOUNT_GWEI
        );

        eigenPodBeacon = new UpgradeableBeacon(address(eigenPodImplementation));

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        delegationImplementation = new EigenLayerDelegation(investmentManager, slasher);
        investmentManagerImplementation = new InvestmentManager(delegation, eigenPodManager, slasher);
        slasherImplementation = new Slasher(investmentManager, delegation);
        eigenPodManagerImplementation = new EigenPodManager(ethPOSDeposit, eigenPodBeacon, investmentManager, slasher);
        eigenPodPaymentEscrowImplementation = new EigenPodPaymentEscrow(eigenPodManager);

        // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(delegation))),
            address(delegationImplementation),
            abi.encodeWithSelector(EigenLayerDelegation.initialize.selector, eigenLayerPauserReg, eigenLayerReputedMultisig)
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(investmentManager))),
            address(investmentManagerImplementation),
            abi.encodeWithSelector(InvestmentManager.initialize.selector, eigenLayerPauserReg, eigenLayerReputedMultisig, INVESTMENT_MANAGER_INIT_PAUSED_STATUS)
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(slasher))),
            address(slasherImplementation),
            abi.encodeWithSelector(Slasher.initialize.selector, eigenLayerPauserReg, eigenLayerReputedMultisig)
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(eigenPodManager))),
            address(eigenPodManagerImplementation),
            abi.encodeWithSelector(
                EigenPodManager.initialize.selector,
                 IBeaconChainOracle(address(0)),
                eigenLayerReputedMultisig,
                eigenLayerPauserReg,
                EIGENPOD_MANAGER_INIT_PAUSED_STATUS
            )
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(eigenPodPaymentEscrow))),
            address(eigenPodPaymentEscrowImplementation),
            abi.encodeWithSelector(EigenPodPaymentEscrow.initialize.selector,
            eigenLayerReputedMultisig,
            eigenLayerPauserReg,
            EIGENPOD_PAYMENT_ESCROW_INIT_PAUSED_STATUS,
            INIT_ESCROW_DELAY_BLOCKS)
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
                    address(eigenLayerProxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, weth, eigenLayerPauserReg)
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
                    address(eigenLayerProxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, eigenToken, eigenLayerPauserReg)
                )
            )
        );

        verifyContract(delegationImplementation, investmentManagerImplementation, slasherImplementation, eigenPodManagerImplementation);
        verifyContract(delegation, investmentManager, slasher, eigenPodManager);
        verifyOwners();
        checkPauserInitializations();
        vm.stopBroadcast();

        vm.writeFile("data/investmentManager.addr", vm.toString(address(investmentManager)));
        vm.writeFile("data/delegation.addr", vm.toString(address(delegation)));
        vm.writeFile("data/slasher.addr", vm.toString(address(slasher)));
        vm.writeFile("data/weth.addr", vm.toString(address(weth)));
        vm.writeFile("data/wethStrat.addr", vm.toString(address(wethStrat)));
        vm.writeFile("data/eigen.addr", vm.toString(address(eigenToken)));
        vm.writeFile("data/eigenStrat.addr", vm.toString(address(eigenStrat)));
        vm.writeFile("data/eigenStrat.addr", vm.toString(address(eigenStrat)));
    }

    function verifyContract(
        EigenLayerDelegation delegationContract,  
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

    function verifyOwners()internal view {
       
        require(investmentManager.owner() == eigenLayerReputedMultisig, "investmentManager owner not set correctly");
        require(delegation.owner() == eigenLayerReputedMultisig, "delegation owner not set correctly");
        require(slasher.owner() == eigenLayerReputedMultisig, "slasher owner not set correctly");
        require(eigenPodManager.owner() == eigenLayerReputedMultisig, "delegation owner not set correctly");

    }
    function checkPauserInitializations() internal view {
        require(address(delegation.pauserRegistry()) == address(eigenLayerPauserReg), "delegation's pauser registry not set correctly");
        require(address(investmentManager.pauserRegistry()) == address(eigenLayerPauserReg), "investmentManager's pauser registry not set correctly");
        require(address(slasher.pauserRegistry()) == address(eigenLayerPauserReg), "slasher's pauser registry not set correctly");

        require(eigenLayerPauserReg.pauser() == address(eigenLayerTeamMultisig), "pauser not set correctly");
        require(eigenLayerPauserReg.unpauser() == eigenLayerReputedMultisig, "pauser not set correctly");
    }
}



    

