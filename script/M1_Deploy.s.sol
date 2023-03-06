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

import "forge-std/Script.sol";
import "forge-std/Test.sol";

// # To load the variables in the .env file
// source .env

// # To deploy and verify our contract
// forge script script/M1_Deploy.s.sol:Deployer_M1 --rpc-url $RPC_URL  --private-key $PRIVATE_KEY --broadcast -vvvv
contract Deployer_M1 is Script, Test {
    Vm cheats = Vm(HEVM_ADDRESS);

    string public deployConfigPath = string(bytes("script/M1_deploy.config.json"));

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
    InvestmentStrategyBase public baseStrategyImplementation;

    EmptyContract public emptyContract;

    // TODO: set these addresses
    address communityMultisig;
    address teamMultisig;

    // the ETH2 deposit contract -- if not on mainnet, we deploy a mock as stand-in
    IETHPOSDeposit public ethPOSDeposit;

    // TODO: add to this token array appropriately -- could include deploying a mock token on testnets
    IERC20[] public tokensForStrategies;
    InvestmentStrategyBase[] public strategyArray;

    // IMMUTABLES TO SET
    uint256 REQUIRED_BALANCE_WEI = 31 ether;
    uint64 MAX_PARTIAL_WTIHDRAWAL_AMOUNT_GWEI = 1 ether / 1e9;

    // OTHER DEPLOYMENT PARAMETERS
    uint256 INVESTMENT_MANAGER_INIT_PAUSED_STATUS;
    uint256 SLASHER_INIT_PAUSED_STATUS;
    uint256 DELEGATION_INIT_PAUSED_STATUS;
    uint256 EIGENPOD_MANAGER_INIT_PAUSED_STATUS;
    uint256 EIGENPOD_PAYMENT_ESCROW_INIT_PAUSED_STATUS;

    // one week in blocks -- 50400
    uint32 INVESTMENT_MANAGER_INIT_WITHDRAWAL_DELAY_BLOCKS;
    uint32 ESCROW_INIT_WITHDRAWAL_DELAY_BLOCKS;

    // TODO: delete this variable
    uint32 PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS = 7 days / 12 seconds;

    function run() external {
        // read the chainID
        uint256 chainId = block.chainid;
        emit log_named_uint("You are deploying on ChainID", chainId);

        // READ JSON CONFIG DATA
        string memory data = vm.readFile(deployConfigPath);
        // bytes memory parsedData = vm.parseJson(data);

        INVESTMENT_MANAGER_INIT_PAUSED_STATUS = stdJson.readUint(data, ".investmentManager.init_paused_status");
        SLASHER_INIT_PAUSED_STATUS = stdJson.readUint(data, ".slasher.init_paused_status");
        DELEGATION_INIT_PAUSED_STATUS = stdJson.readUint(data, ".delegation.init_paused_status");
        EIGENPOD_MANAGER_INIT_PAUSED_STATUS = stdJson.readUint(data, ".eigenPodManager.init_paused_status");
        EIGENPOD_PAYMENT_ESCROW_INIT_PAUSED_STATUS = stdJson.readUint(data, ".eigenPodPaymentEscrow.init_paused_status");

        // TODO: check these somewhere
        INVESTMENT_MANAGER_INIT_WITHDRAWAL_DELAY_BLOCKS = uint32(stdJson.readUint(data, ".investmentManager.init_withdrawal_delay_blocks"));
        ESCROW_INIT_WITHDRAWAL_DELAY_BLOCKS = uint32(stdJson.readUint(data, ".investmentManager.init_withdrawal_delay_blocks"));
        // if on mainnet, use mainnet config
        if (chainId == 1) {
            communityMultisig = stdJson.readAddress(data, ".multisig_addresses.mainnet.communityMultisig");
            teamMultisig = stdJson.readAddress(data, ".multisig_addresses.mainnet.teamMultisig");
        // if not on mainnet, read from the "testnet" config
        } else {
            communityMultisig = stdJson.readAddress(data, ".multisig_addresses.testnet.communityMultisig");
            teamMultisig = stdJson.readAddress(data, ".multisig_addresses.testnet.teamMultisig");
        }

        require(communityMultisig != address(0), "communityMultisig address not configured correctly!");
        require(teamMultisig != address(0), "teamMultisig address not configured correctly!");

        // START RECORDING TRANSACTIONS FOR DEPLOYMENT
        vm.startBroadcast();

        // deploy proxy admin for ability to upgrade proxy contracts
        eigenLayerProxyAdmin = new ProxyAdmin();

        //deploy pauser registry
        eigenLayerPauserReg = new PauserRegistry(teamMultisig, communityMultisig);

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

        // if on mainnet, use the ETH2 deposit contract address
        if (chainId == 1) {
            ethPOSDeposit = IETHPOSDeposit(0x00000000219ab540356cBB839Cbe05303d7705Fa);
        // if not on mainnet, deploy a mock
        } else {
            ethPOSDeposit = new ETHPOSDepositMock();
        }
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
            abi.encodeWithSelector(
                EigenLayerDelegation.initialize.selector,
                communityMultisig,
                eigenLayerPauserReg,
                DELEGATION_INIT_PAUSED_STATUS
            )
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(investmentManager))),
            address(investmentManagerImplementation),
            abi.encodeWithSelector(
                InvestmentManager.initialize.selector,
                communityMultisig,
                eigenLayerPauserReg,
                INVESTMENT_MANAGER_INIT_PAUSED_STATUS,
                INVESTMENT_MANAGER_INIT_WITHDRAWAL_DELAY_BLOCKS
            )
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(slasher))),
            address(slasherImplementation),
            abi.encodeWithSelector(
                Slasher.initialize.selector,
                communityMultisig,
                eigenLayerPauserReg,
                SLASHER_INIT_PAUSED_STATUS
            )
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(eigenPodManager))),
            address(eigenPodManagerImplementation),
            abi.encodeWithSelector(
                EigenPodManager.initialize.selector,
                // TODO: change this?
                IBeaconChainOracle(address(0)),
                communityMultisig,
                eigenLayerPauserReg,
                EIGENPOD_MANAGER_INIT_PAUSED_STATUS
            )
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(eigenPodPaymentEscrow))),
            address(eigenPodPaymentEscrowImplementation),
            abi.encodeWithSelector(EigenPodPaymentEscrow.initialize.selector,
            communityMultisig,
            eigenLayerPauserReg,
            EIGENPOD_PAYMENT_ESCROW_INIT_PAUSED_STATUS,
            ESCROW_INIT_WITHDRAWAL_DELAY_BLOCKS)
        );

        // deploy InvestmentStrategyBase contract implementation, then create upgradeable proxy that points to implementation and initialize it
        baseStrategyImplementation = new InvestmentStrategyBase(investmentManager);
        for (uint256 i = 0; i < tokensForStrategies.length; ++i) {
            strategyArray.push(
                InvestmentStrategyBase(address(
                    new TransparentUpgradeableProxy(
                        address(baseStrategyImplementation),
                        address(eigenLayerProxyAdmin),
                        abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, tokensForStrategies[i], eigenLayerPauserReg)
                    )
                ))
            );
        }

        eigenLayerProxyAdmin.transferOwnership(communityMultisig);

        // STOP RECORDING TRANSACTIONS FOR DEPLOYMENT
        vm.stopBroadcast();


        // CONFIRM DEPLOYMENT
        _verifyContractsPointAtOneAnother(
            delegationImplementation,
            investmentManagerImplementation,
            slasherImplementation,
            eigenPodManagerImplementation,
            eigenPodPaymentEscrowImplementation
        );
        _verifyContractsPointAtOneAnother(
            delegation,
            investmentManager,
            slasher,
            eigenPodManager,
            eigenPodPaymentEscrow
        );
        _verifyInitialOwners();
        _checkPauserInitializations();
        _verifyInitializationParams();


        // WRITE JSON DATA
        string memory parent_object = "parent object";

        string memory deployed_addresses = "deployed addresses";
        vm.serializeAddress(deployed_addresses, "eigenLayerProxyAdmin", address(eigenLayerProxyAdmin));
        vm.serializeAddress(deployed_addresses, "eigenLayerPauserReg", address(eigenLayerPauserReg));
        vm.serializeAddress(deployed_addresses, "slasher", address(slasher));
        vm.serializeAddress(deployed_addresses, "slasherImplementation", address(slasherImplementation));
        vm.serializeAddress(deployed_addresses, "delegation", address(delegation));
        vm.serializeAddress(deployed_addresses, "delegationImplementation", address(delegationImplementation));
        vm.serializeAddress(deployed_addresses, "investmentManager", address(investmentManager));
        vm.serializeAddress(deployed_addresses, "investmentManagerImplementation", address(investmentManagerImplementation));
        vm.serializeAddress(deployed_addresses, "eigenPodManager", address(eigenPodManager));
        vm.serializeAddress(deployed_addresses, "eigenPodManagerImplementation", address(eigenPodManagerImplementation));
        vm.serializeAddress(deployed_addresses, "eigenPodPaymentEscrow", address(eigenPodPaymentEscrow));
        vm.serializeAddress(deployed_addresses, "eigenPodPaymentEscrowImplementation", address(eigenPodPaymentEscrowImplementation));
        vm.serializeAddress(deployed_addresses, "eigenPodBeacon", address(eigenPodBeacon));
        vm.serializeAddress(deployed_addresses, "eigenPodImplementation", address(eigenPodImplementation));
        vm.serializeAddress(deployed_addresses, "baseStrategyImplementation", address(baseStrategyImplementation));
        vm.serializeAddress(deployed_addresses, "emptyContract", address(emptyContract));
        string memory deployed_addresses_output = vm.serializeAddress(deployed_addresses, "delegation", address(delegation));

        string memory parameters = "parameters";
        vm.serializeAddress(parameters, "communityMultisig", communityMultisig);
        string memory parameters_output = vm.serializeAddress(parameters, "teamMultisig", teamMultisig);

        string memory chain_info = "chain info";
        string memory chain_info_output = vm.serializeUint(chain_info, "chainId", chainId);

        vm.serializeString(parent_object, deployed_addresses, deployed_addresses_output);
        vm.serializeString(parent_object, chain_info, chain_info_output);
        string memory finalJson = vm.serializeString(parent_object, parameters, parameters_output);
        vm.writeJson(finalJson, "script/output/M1_deployment_data.json");
    }

    function _verifyContractsPointAtOneAnother(
        EigenLayerDelegation delegationContract,  
        InvestmentManager investmentManagerContract, 
        Slasher slasherContract,  
        EigenPodManager eigenPodManagerContract,
        EigenPodPaymentEscrow eigenPodPaymentEscrowContract
    ) internal view {
        require(delegationContract.slasher() == slasher, "delegation: slasher address not set correctly");
        require(delegationContract.investmentManager() == investmentManager, "delegation: investmentManager address not set correctly");

        require(investmentManagerContract.slasher() == slasher, "investmentManager: slasher address not set correctly");
        require(investmentManagerContract.delegation() == delegation, "investmentManager: delegation address not set correctly");
        require(investmentManagerContract.eigenPodManager() == eigenPodManager, "investmentManager: eigenPodManager address not set correctly");

        require(slasherContract.investmentManager() == investmentManager, "slasher: investmentManager not set correctly");
        require(slasherContract.delegation() == delegation, "slasher: delegation not set correctly");

        require(eigenPodManagerContract.ethPOS() == ethPOSDeposit, " eigenPodManager: ethPOSDeposit contract address not set correctly");
        require(eigenPodManagerContract.eigenPodBeacon() == eigenPodBeacon, "eigenPodManager: eigenPodBeacon contract address not set correctly");
        require(eigenPodManagerContract.investmentManager() == investmentManager, "eigenPodManager: investmentManager contract address not set correctly");
        require(eigenPodManagerContract.slasher() == slasher, "eigenPodManager: slasher contract address not set correctly");
        require(eigenPodManagerContract.beaconChainOracle() == IBeaconChainOracle(address(0)), "eigenPodManager: eigenPodBeacon contract address not set correctly");

        require(eigenPodPaymentEscrowContract.eigenPodManager() == eigenPodManager, "eigenPodPaymentEscrowContract: eigenPodManager address not set correctly");
    }

    function _verifyInitialOwners()internal view {
        require(investmentManager.owner() == communityMultisig, "investmentManager: owner not set correctly");
        require(delegation.owner() == communityMultisig, "delegation: owner not set correctly");
        require(slasher.owner() == communityMultisig, "slasher: owner not set correctly");
        require(eigenPodManager.owner() == communityMultisig, "delegation: owner not set correctly");

        require(eigenLayerProxyAdmin.owner() == communityMultisig, "investmentManager: owner not set correctly");
    }

    function _checkPauserInitializations() internal view {
        require(delegation.pauserRegistry() == eigenLayerPauserReg, "delegation: pauser registry not set correctly");
        require(investmentManager.pauserRegistry() == eigenLayerPauserReg, "investmentManager: pauser registry not set correctly");
        require(slasher.pauserRegistry() == eigenLayerPauserReg, "slasher: pauser registry not set correctly");

        require(eigenLayerPauserReg.pauser() == teamMultisig, "pauserRegistry: pauser not set correctly");
        require(eigenLayerPauserReg.unpauser() == communityMultisig, "pauserRegistry: unpauser not set correctly");

        // // pause *nothing*
        // uint256 INVESTMENT_MANAGER_INIT_PAUSED_STATUS = 0;
        // // pause *everything*
        // uint256 SLASHER_INIT_PAUSED_STATUS = type(uint256).max; 
        // // pause *everything*
        // uint256 DELEGATION_INIT_PAUSED_STATUS = type(uint256).max;  
        // // pause *all of the proof-related functionality* (everything that can be paused other than creation of EigenPods)
        // uint256 EIGENPOD_MANAGER_INIT_PAUSED_STATUS = (2**1) + (2**2) + (2**3) + (2**4); /* = 30 */ 
        // // pause *nothing*
        // uint256 EIGENPOD_PAYMENT_ESCROW_INIT_PAUSED_STATUS = 0;
        require(investmentManager.paused() == 0, "investmentManager: init paused status set incorrectly");
        require(slasher.paused() == type(uint256).max, "slasher: init paused status set incorrectly");
        require(delegation.paused() == type(uint256).max, "delegation: init paused status set incorrectly");
        require(eigenPodManager.paused() == 30, "eigenPodManager: init paused status set incorrectly");
        require(eigenPodPaymentEscrow.paused() == 0, "eigenPodPaymentEscrow: init paused status set incorrectly");
    }

    function _verifyInitializationParams() internal view {
        // // one week in blocks -- 50400
        // uint32 INVESTMENT_MANAGER_INIT_WITHDRAWAL_DELAY_BLOCKS = 7 days / 12 seconds;
        // uint32 ESCROW_INIT_WITHDRAWAL_DELAY_BLOCKS = 7 days / 12 seconds;
        require(investmentManager.withdrawalDelayBlocks() == 7 days / 12 seconds,
            "investmentManager: withdrawalDelayBlocks initialized incorrectly");
        require(eigenPodPaymentEscrow.withdrawalDelayBlocks() == 7 days / 12 seconds,
            "eigenPodPaymentEscrow: withdrawalDelayBlocks initialized incorrectly");
    }
}



    

