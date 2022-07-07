// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./mock/DepositContract.sol";

import "./core/Eigen.sol";

import "./core/EigenLayrDelegation.sol";
import "./core/EigenLayrDeposit.sol";

import "./investment/InvestmentManager.sol";
import "./investment/InvestmentStrategyBase.sol";
import "./investment/Slasher.sol";

import "./middleware/ServiceFactory.sol";
import "./middleware/Repository.sol";
import "./middleware/DataLayr/DataLayr.sol";
import "./middleware/DataLayr/DataLayrServiceManager.sol";
import "./middleware/DataLayr/DataLayrRegistry.sol";
import "./middleware/DataLayr/DataLayrPaymentChallenge.sol";

import "./middleware/DataLayr/DataLayrEphemeralKeyRegistry.sol";
import "./middleware/DataLayr/DataLayrChallengeUtils.sol";
import "./middleware/DataLayr/DataLayrLowDegreeChallenge.sol";
import "./middleware/DataLayr/DataLayrDisclosureChallenge.sol";

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";


import "./utils/ERC165_Universal.sol";
import "./utils/ERC1155TokenReceiver.sol";

import "./libraries/BytesLib.sol";
import "./libraries/SignatureCompaction.sol";

contract EigenLayrDeployer is ERC165_Universal, ERC1155TokenReceiver {
    using BytesLib for bytes;

    DepositContract public depositContract;
    // Eigen public eigen;
    IERC20 public eigenToken;
    InvestmentStrategyBase public eigenStrat;
    EigenLayrDelegation public delegation;
    EigenLayrDeposit public deposit;
    InvestmentManager public investmentManager;
    DataLayrEphemeralKeyRegistry public ephemeralKeyRegistry;
    Slasher public slasher;
    ServiceFactory public serviceFactory;
    DataLayrRegistry public dlReg;
    DataLayrServiceManager public dlsm;
    DataLayr public dl;

    IERC20 public weth;
    InvestmentStrategyBase public strat;
    IRepository public dlRepository;

    DataLayrPaymentChallenge public dataLayrPaymentChallenge;
    DataLayrDisclosureChallenge public dataLayrDisclosureChallenge;

    uint256 wethInitialSupply = 10e50;
    uint256 undelegationFraudProofInterval = 7 days;
    uint256 consensusLayerEthToEth = 10;
    bytes32 consensusLayerDepositRoot =
        0x9c4bad94539254189bb933df374b1c2eb9096913a1f6a3326b84133d2b9b9bad;
    address storer = address(420);
    address registrant = address(0x4206904396bF2f8b173350ADdEc5007A52664293); //sk: e88d9d864d5d731226020c5d2f02b62a4ce2a4534a39c225d32d3db795f83319
    address ownerAddr =  address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);

    //from testing seed phrase
    bytes32 priv_key_0 = 0x1234567812345678123456781234567812345678123456781234567812345678;



    constructor() {
        //eth2 deposit contract
        depositContract = new DepositContract();
        //deploy eigen. send eigen tokens to an address where they won't trigger failure for 'transfer to non ERC1155Receiver implementer,'
        // eigen = new Eigen(ownerAddr);

        deposit = new EigenLayrDeposit(consensusLayerDepositRoot);
        //do stuff this eigen token here
        delegation = new EigenLayrDelegation();
        slasher = new Slasher(investmentManager, address(this));
        serviceFactory = new ServiceFactory(investmentManager, delegation);
        investmentManager = new InvestmentManager(delegation);
        //used in the one ETH investment strategy
        weth = new ERC20PresetFixedSupply(
            "weth",
            "WETH",
            wethInitialSupply,
            ownerAddr
        );
        //do stuff with weth
        strat = new InvestmentStrategyBase();
        strat.initialize(address(investmentManager), weth);

        IInvestmentStrategy[] memory strats = new IInvestmentStrategy[](1);
        strats[0] = IInvestmentStrategy(address(strat));

        //used in the one EIGEN investment strategy
        eigenToken = new ERC20PresetFixedSupply(
            "eigen",
            "EIGEN",
            wethInitialSupply,
            ownerAddr
        );
        //do stuff with eigen
        eigenStrat = new InvestmentStrategyBase();
        eigenStrat.initialize(address(investmentManager), eigenToken);

        address governor = address(this);
        investmentManager.initialize(
            strats,
            slasher,
            governor,
            address(deposit)
        );

        delegation.initialize(
            investmentManager,
            undelegationFraudProofInterval
        );

        dataLayrPaymentChallenge= new DataLayrPaymentChallenge(
            weth,
            dlsm
        );
        // dataLayrDisclosureChallenge = new DataLayrDisclosureChallenge();

        DataLayrChallengeUtils disclosureUtils = new DataLayrChallengeUtils();

        dlRepository = new Repository(delegation, investmentManager);

        uint256 feePerBytePerTime = 1;
        dlsm = new DataLayrServiceManager(
            delegation,
            dlRepository,
            weth,
            feePerBytePerTime
        );

        dl = new DataLayr(dlRepository);

        ephemeralKeyRegistry = new DataLayrEphemeralKeyRegistry(dlRepository);
        
        VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[] memory ethStratsAndMultipliers = new VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[](1);
        ethStratsAndMultipliers[0].strategy = strat;
        ethStratsAndMultipliers[0].multiplier = 1e18;
        VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[] memory eigenStratsAndMultipliers = new VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[](1);
        eigenStratsAndMultipliers[0].strategy = eigenStrat;
        eigenStratsAndMultipliers[0].multiplier = 1e18;
        dlReg = new DataLayrRegistry(Repository(address(dlRepository)), delegation, investmentManager, ephemeralKeyRegistry, ethStratsAndMultipliers, eigenStratsAndMultipliers);

        DataLayrLowDegreeChallenge lowDegreeChallenge = new DataLayrLowDegreeChallenge(dlsm, dl, dlReg, disclosureUtils);

        Repository(address(dlRepository)).initialize(
            dlReg,
            dlsm,
            dlReg,
            address(this)
        );

        dlsm.setDataLayr(dl);
        dlsm.setLowDegreeChallenge(lowDegreeChallenge);

        deposit.initialize(depositContract, investmentManager, dlsm);
    }
}