// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


import "../src/contracts/core/Eigen.sol";

import "../src/contracts/interfaces/IEigenLayrDelegation.sol";
import "../src/contracts/core/EigenLayrDelegation.sol";

import "../src/contracts/investment/InvestmentManager.sol";
import "../src/contracts/investment/InvestmentStrategyBase.sol";
import "../src/contracts/investment/HollowInvestmentStrategy.sol";
import "../src/contracts/investment/Slasher.sol";

import "../src/contracts/middleware/ServiceFactory.sol";
import "../src/contracts/middleware/Repository.sol";
import "../src/contracts/middleware/DataLayr/DataLayrServiceManager.sol";
import "../src/contracts/middleware/BLSRegistryWithBomb.sol";
import "../src/contracts/middleware/DataLayr/DataLayrPaymentManager.sol";
import "../src/contracts/middleware/EphemeralKeyRegistry.sol";
import "../src/contracts/middleware/DataLayr/DataLayrChallengeUtils.sol";
import "../src/contracts/middleware/DataLayr/DataLayrLowDegreeChallenge.sol";
import "../src/contracts/middleware/DataLayr/DataLayrDisclosureChallenge.sol";

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
import "../src/contracts/libraries/DataStoreHash.sol";

// # To load the variables in the .env file
// source .env

// # To deploy and verify our contract
// forge script script/Deployer.s.sol:EigenLayrDeployer --rpc-url $RPC_URL  --private-key $PRIVATE_KEY --broadcast -vvvv

//TODO: encode data properly so that we initialize TransparentUpgradeableProxy contracts in their constructor rather than a separate call (if possible)
contract EigenLayrDeployer is
    Script,
    DSTest,
    ERC165_Universal,
    ERC1155TokenReceiver
    //,
    // Signers,
    // SignatureUtils
{
    using BytesLib for bytes;

    Vm cheats = Vm(HEVM_ADDRESS);

    uint256 public constant DURATION_SCALE = 1 hours;
    // Eigen public eigen;
    IERC20 public eigenToken;
    InvestmentStrategyBase public eigenStrat;
    EigenLayrDelegation public delegation;
    InvestmentManager public investmentManager;
    EphemeralKeyRegistry public ephemeralKeyRegistry;
    Slasher public slasher;
    ServiceFactory public serviceFactory;
    BLSRegistryWithBomb public dlReg;
    DataLayrServiceManager public dlsm;
    DataLayrLowDegreeChallenge public dlldc;

    IERC20 public weth;
    InvestmentStrategyBase public strat;
    IRepository public dlRepository;

    ProxyAdmin public eigenLayrProxyAdmin;

    DataLayrPaymentManager public dataLayrPaymentManager;
    DataLayrDisclosureChallenge public dataLayrDisclosureChallenge;

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

    bytes32 public ephemeralKey =
        0x3290567812345678123456781234577812345698123456781234567812344389;

    uint256 public constant eigenTokenId = 0;
    uint256 public constant eigenTotalSupply = 1000e18;

    uint256 mainHonchoPrivKey = vm.envUint("PRIVATE_KEY_UINT");

    address mainHoncho = cheats.addr(mainHonchoPrivKey);
    

    //     0x1234567812345678123456781234567812345698123456781234567812348976;
    // address acct_1 = cheats.addr(uint256(priv_key_1));

    // address mainHoncho = address(0x22718436a53D0Fb585A5AE52FcDd0Bc03416b0ff);

    uint8 durationToInit = 2;

    //performs basic deployment before each test
    function run() external {

        vm.startBroadcast();

        emit log_address(mainHoncho);
        // deploy proxy admin for ability to upgrade proxy contracts
        eigenLayrProxyAdmin = new ProxyAdmin();

        // deploy delegation contract implementation, then create upgradeable proxy that points to implementation
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
        vm.writeFile("deployedAddresses/investmentManager", vm.toString(address(investmentManager)));

        //simple ERC20 (*NOT WETH-like!), used in a test investment strategy
        weth = new ERC20PresetFixedSupply(
            "weth",
            "WETH",
            wethInitialSupply,
            msg.sender
        );
        vm.writeFile("deployedAddresses/weth", vm.toString(address(weth)));

        // deploy InvestmentStrategyBase contract implementation, then create upgradeable proxy that points to implementation
        strat = new InvestmentStrategyBase();
        strat = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(strat),
                    address(eigenLayrProxyAdmin),
                    ""
                )
            )
        );
        // initialize InvestmentStrategyBase proxy
        strat.initialize(address(investmentManager), weth);
        vm.writeLine("deployedAddresses/wethStrat", vm.toString(address(strat)));

        eigenToken = new ERC20PresetFixedSupply(
            "eigen",
            "EIGEN",
            wethInitialSupply,
            msg.sender
        );
        vm.writeFile("deployedAddresses/eigen", vm.toString(address(eigenToken)));
        // deploy InvestmentStrategyBase contract implementation, then create upgradeable proxy that points to implementation
        eigenStrat = new InvestmentStrategyBase();
        eigenStrat = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(eigenStrat),
                    address(eigenLayrProxyAdmin),
                    ""
                )
            )
        );
        vm.writeFile("deployedAddresses/eigenStrat", vm.toString(address(eigenStrat)));
        // initialize InvestmentStrategyBase proxy
        eigenStrat.initialize(address(investmentManager), eigenToken);

        // create 'HollowInvestmentStrategy' contracts for 'ConsenusLayerEth' and 'ProofOfStakingEth'
        IInvestmentStrategy[] memory strats = new IInvestmentStrategy[](2);
        HollowInvestmentStrategy temp = new HollowInvestmentStrategy();
        temp.initialize(address(investmentManager));
        strats[0] = temp;
        strategies[0] = temp;
        temp = new HollowInvestmentStrategy();
        temp.initialize(address(investmentManager));
        strats[1] = temp;
        strategies[1] = temp;
        // add WETH strategy to mapping
        strategies[2] = IInvestmentStrategy(address(strat));

        // actually initialize the investmentManager (proxy) contraxt
        address governor = address(this);
        // deploy slasher and service factory contracts
        slasher = new Slasher();
        slasher.initialize(investmentManager, delegation, governor);
        serviceFactory = new ServiceFactory(investmentManager, delegation);

        investmentManager.initialize(
            slasher,
            governor
        );

        // initialize the delegation (proxy) contract
        delegation.initialize(
            investmentManager,
            undelegationFraudProofInterval
        );

        vm.writeFile("deployedAddresses/delegation", vm.toString(address(delegation)));

        // deploy all the DataLayr contracts
        address dlsm = _deployDataLayrContracts();

        // // set up a strategy for a mock liquid staking token
        // liquidStakingMockToken = new ERC20PresetFixedSupply();
        // liquidStakingMockStrat = new InvestmentStrategyBase();
        // liquidStakingMockStrat.initialize(
        //     address(investmentManager),
        //     IERC20(address(liquidStakingMockToken))
        // );

        vm.stopBroadcast();

        // _allocateAsset(dlsm);
    }

    function _allocateAsset(address dlsm) internal {
        // read meta data from json
        string memory json = vm.readFile("config.json");
        uint numDis = stdJson.readUint(json, ".numDis");
        uint numDln = stdJson.readUint(json, ".numDln");
        uint numStaker = stdJson.readUint(json, ".numStaker");
        uint numCha = stdJson.readUint(json, ".numCha");

        emit log("numstaker");
        emit log_uint(numStaker);
        

        uint256 wethAmount = eigenTotalSupply / (numStaker + numDis + 50); // save 100 portions

        emit log("wethAmount");
        emit log_uint(wethAmount);
        vm.startBroadcast(msg.sender);
        // deployer allocate weth, eigen to staker
        for (uint i = 0; i < numStaker ; ++i) {
            address stakerAddr = stdJson.readAddress(json, string.concat(".staker[", string.concat(vm.toString(i), "].address")));    
            weth.transfer(stakerAddr, wethAmount);
            eigenToken.transfer(stakerAddr, wethAmount);
            emit log("stakerAddr");
            emit log_address(stakerAddr);
        }
        // deployer allocate weth, eigen to disperser
        for (uint i = 0; i < numDis ; ++i) {
            address disAddr = stdJson.readAddress(json, string.concat(".dis[", string.concat(vm.toString(i), "].address")));    
            weth.transfer(disAddr, wethAmount);
            emit log("disAddr");
            emit log_address(disAddr);
        }

        vm.stopBroadcast();

        // dln, staker delegations        
        for (uint i = 0; i < numDln ; ++i) {
            uint256 stakerPrivKeyUint = convertString(stdJson.readString(json, string.concat(".staker[", string.concat(vm.toString(i), "].private"))));
            uint256 dlnPrivKeyUint = convertString(stdJson.readString(json, string.concat(".dln[", string.concat(vm.toString(i), "].private"))));

            address stakerAddr = stdJson.readAddress(json, string.concat(".staker[", string.concat(vm.toString(i), "].address")));  
            address dlnAddr = stdJson.readAddress(json, string.concat(".dln[", string.concat(vm.toString(i), "].address")));

            // not sure it is used ?
            //vm.broadcast(dlnPrivKeyUint);
            //ServiceFactory delegationTerm = new ServiceFactory(investmentManager, delegation);

            emit log("stakerAddr");
            emit log_address(stakerAddr);
            emit log_address(dlnAddr);
            emit log_uint(dlnPrivKeyUint);
            emit log_uint(i);
            
            vm.broadcast(dlnAddr);

            // /*
            // delegation.registerAsDelegate(IDelegationTerms(dlnAddr));

            // vm.broadcast(stakerPrivKeyUint);
            // eigenToken.approve(address(investmentManager), wethAmount);
            
            // vm.broadcast(stakerPrivKeyUint);
            // investmentManager.depositIntoStrategy(stakerAddr, eigenStrat, eigenToken, wethAmount);

            // vm.broadcast(stakerPrivKeyUint);
            // weth.approve(address(investmentManager), wethAmount);

            // vm.broadcast(stakerPrivKeyUint);
            // investmentManager.depositIntoStrategy(stakerAddr, strat, weth, wethAmount);

            // vm.broadcast(stakerPrivKeyUint);
            // investmentManager.investorStratShares(stakerAddr, strat);

            // vm.broadcast(stakerPrivKeyUint);
            // delegation.delegateTo(dlnAddr);
            // */
        }
        emit log("aaaa");
        
        for (uint i = 0; i < numDis ; ++i) {
            uint256 disPrivKeyUint = convertString(stdJson.readString(json, string.concat(".dis[", string.concat(vm.toString(i), "].private"))));
            address disAddr = stdJson.readAddress(json, string.concat(".dis[", string.concat(vm.toString(i), "].address")));

            vm.broadcast(disPrivKeyUint);
            weth.approve(dlsm, wethAmount);
        }
        
    }



    // deploy all the DataLayr contracts. Relies on many EL contracts having already been deployed.
    function _deployDataLayrContracts() internal returns (address dlsmAddress) {
        DataLayrChallengeUtils challengeUtils = new DataLayrChallengeUtils();

        dlRepository = new Repository(delegation, investmentManager);
        vm.writeFile("deployedAddresses/dlRepository", vm.toString(address(dlRepository)));

        uint256 feePerBytePerTime = 1;
        dlsm = new DataLayrServiceManager(
            investmentManager,
            delegation,
            dlRepository,
            weth,
            feePerBytePerTime
        );
        vm.writeFile("deployedAddresses/dlsm", vm.toString(address(dlsm)));

        uint256 paymentFraudProofCollateral = 1 wei;
        dataLayrPaymentManager = new DataLayrPaymentManager(
            weth,
            paymentFraudProofCollateral,
            dlsm
        );

        ephemeralKeyRegistry = new EphemeralKeyRegistry(dlRepository);

        VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[]
            memory ethStratsAndMultipliers = new VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[](
                3
            );
        for (uint256 i = 0; i < ethStratsAndMultipliers.length; ++i) {
            ethStratsAndMultipliers[i].strategy = strategies[i];
            // TODO: change this if needed
            ethStratsAndMultipliers[i].multiplier = 1e18;
        }
        VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[]
            memory eigenStratsAndMultipliers = new VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[](
                1
            );
        eigenStratsAndMultipliers[0].strategy = eigenStrat;
        eigenStratsAndMultipliers[0].multiplier = 1e18;
        uint8 _NUMBER_OF_QUORUMS = 2;
        dlReg = new BLSRegistryWithBomb(
            Repository(address(dlRepository)),
            delegation,
            investmentManager,
            ephemeralKeyRegistry,
            _NUMBER_OF_QUORUMS,
            ethStratsAndMultipliers,
            eigenStratsAndMultipliers
        );
        vm.writeFile("deployedAddresses/dlReg", vm.toString(address(dlReg)));

        Repository(address(dlRepository)).initialize(
            dlReg,
            dlsm,
            dlReg,
            mainHoncho
        );
        emit log_address(dlRepository.owner());
        dlldc = new DataLayrLowDegreeChallenge(dlsm, dlReg, challengeUtils);
        dataLayrDisclosureChallenge = new DataLayrDisclosureChallenge(
            dlsm,
            dlReg,
            challengeUtils
        );
        dlsm.setLowDegreeChallenge(dlldc);
        dlsm.setDisclosureChallenge(dataLayrDisclosureChallenge);
        dlsm.setPaymentManager(dataLayrPaymentManager);
        dlsm.setEphemeralKeyRegistry(ephemeralKeyRegistry);

        dlsmAddress = address(dlsm);
    }


    function numberFromAscII(bytes1 b) private pure returns (uint8 res) {
        if (b>="0" && b<="9") {
            return uint8(b) - uint8(bytes1("0"));
        } else if (b>="A" && b<="F") {
            return 10 + uint8(b) - uint8(bytes1("A"));
        } else if (b>="a" && b<="f") {
            return 10 + uint8(b) - uint8(bytes1("a"));
        }
        return uint8(b); // or return error ... 
    }

   

    function convertString(string memory str) public pure returns (uint256 value) {
        
        bytes memory b = bytes(str);
        uint256 number = 0;
        for(uint i=0;i<b.length;i++){
            number = number << 4; // or number = number * 16 
            number |= numberFromAscII(b[i]); // or number += numberFromAscII(b[i]);
        }
        return number; 
    }

}
