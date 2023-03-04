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

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

// # To load the variables in the .env file
// source .env

// # To deploy and verify our contract
// forge script script/M1_Deploy.s.sol:Deployer_M1 --rpc-url $RPC_URL  --private-key $PRIVATE_KEY --broadcast -vvvv
contract Deployer_M1 is Script, Owners {
    using stdJson for string;

    Vm cheats = Vm(HEVM_ADDRESS);

    string public deployConfigPath = string(bytes("./M1_deploy.config.json"));

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
    address communityMultisig = address(2);
    address teamMultisig = address(3);

    // TODO: set this correctly instead of using a mock (possibly dependent upon network)
    IETHPOSDeposit public ethPOSDeposit;

    // TODO: add to this token array appropriately -- could include deploying a mock token on testnets
    IERC20[] public tokensForStrategies;
    InvestmentStrategyBase[] public strategyArray;

    // IMMUTABLES TO SET
    // one week in blocks
    uint32 PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS = 7 days / 12 seconds;
    uint256 REQUIRED_BALANCE_WEI = 31 ether;
    uint64 MAX_PARTIAL_WTIHDRAWAL_AMOUNT_GWEI = 1 ether / 1e9;

    // OTHER DEPLOYMENT PARAMETERS
    // pause *nothing*
    uint256 INVESTMENT_MANAGER_INIT_PAUSED_STATUS = 0;
    // one week in blocks
    uint32 WITHDRAWAL_DELAY_BLOCKS = 7 days / 12 seconds;

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
        string memory data = vm.readFile(deployConfigPath);
        bytes memory parsedData = vm.parseJson(data);
        // TODO: parse data -- see docs here https://book.getfoundry.sh/cheatcodes/parse-json#decoding-json-objects-into-solidity-structs

        // RawEIP1559ScriptArtifact memory rawArtifact = abi.decode(parsedData, (RawEIP1559ScriptArtifact));
        // EIP1559ScriptArtifact memory artifact;
        // artifact.libraries = rawArtifact.libraries;
        // artifact.path = rawArtifact.path;
        // artifact.timestamp = rawArtifact.timestamp;
        // artifact.pending = rawArtifact.pending;
        // artifact.txReturns = rawArtifact.txReturns;
        // artifact.receipts = rawToConvertedReceipts(rawArtifact.receipts);
        // artifact.transactions = rawToConvertedEIPTx1559s(rawArtifact.transactions);

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
                WITHDRAWAL_DELAY_BLOCKS
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
            INIT_ESCROW_DELAY_BLOCKS)
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
        vm.stopBroadcast();

        // TODO: write to file using vm.writeJSON -- see https://github.com/foundry-rs/foundry/pull/3595 or https://book.getfoundry.sh/cheatcodes/serialize-json
        string memory obj1 = "some key";
        vm.serializeBool(obj1, "boolean", true);
        vm.serializeUint(obj1, "number", uint256(342));

        string memory obj2 = "some other key";
        string memory output = vm.serializeString(obj2, "title", "finally json serialization");

        // IMPORTANT: This works because `serializeString` first tries to interpret `output` as
        //   a stringified JSON object. If the parsing fails, then it treats it as a normal
        //   string instead.
        //   For instance, an `output` equal to '{ "ok": "asd" }' will produce an object, but
        //   an output equal to '"ok": "asd" }' will just produce a normal string.
        string memory finalJson = vm.serializeString(obj1, "object", output);

        vm.writeJson(finalJson, "./output/example.json");
        // vm.writeFile("data/investmentManager.addr", vm.toString(address(investmentManager)));
        // vm.writeFile("data/delegation.addr", vm.toString(address(delegation)));
        // vm.writeFile("data/slasher.addr", vm.toString(address(slasher)));
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

        require(investmentManager.paused() == INVESTMENT_MANAGER_INIT_PAUSED_STATUS, "investmentManager init paused status set incorrectly");
        require(slasher.paused() == SLASHER_INIT_PAUSED_STATUS, "slasher init paused status set incorrectly");
        require(delegation.paused() == DELEGATION_INIT_PAUSED_STATUS, "delegation init paused status set incorrectly");
        require(eigenPodManager.paused() == EIGENPOD_MANAGER_INIT_PAUSED_STATUS, "eigenPodManager init paused status set incorrectly");
        require(eigenPodPaymentEscrow.paused() == EIGENPOD_PAYMENT_ESCROW_INIT_PAUSED_STATUS, "eigenPodPaymentEscrow init paused status set incorrectly");
    }
}



    

