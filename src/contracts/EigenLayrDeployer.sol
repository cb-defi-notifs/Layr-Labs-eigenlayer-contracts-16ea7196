// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./mock/DepositContract.sol";
import "./governance/Timelock.sol";

import "./core/Eigen.sol";

import "./core/EigenLayrDelegation.sol";
import "./core/EigenLayrDeposit.sol";

import "./investment/InvestmentManager.sol";
import "./investment/WethStashInvestmentStrategy.sol";
import "./investment/Slasher.sol";

import "./middleware/ServiceFactory.sol";
import "./middleware/Repository.sol";
import "./middleware/DataLayr/DataLayr.sol";
import "./middleware/DataLayr/DataLayrServiceManager.sol";
import "./middleware/DataLayr/DataLayrVoteWeigher.sol";
import "./middleware/DataLayr/DataLayrPaymentChallengeFactory.sol";
import "./middleware/DataLayr/DataLayrDisclosureChallengeFactory.sol";

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";


import "./utils/ERC165_Universal.sol";
import "./utils/ERC1155TokenReceiver.sol";

import "./libraries/BytesLib.sol";
import "./libraries/SignatureCompaction.sol";

contract EigenLayrDeployer is ERC165_Universal, ERC1155TokenReceiver {
    using BytesLib for bytes;

    DepositContract public depositContract;
    Eigen public eigen;
    EigenLayrDelegation public delegation;
    EigenLayrDeposit public deposit;
    InvestmentManager public investmentManager;
    Slasher public slasher;
    ServiceFactory public serviceFactory;
    DataLayrVoteWeigher public dlRegVW;
    DataLayrServiceManager public dlsm;
    DataLayr public dl;

    IERC20 public weth;
    WethStashInvestmentStrategy public strat;
    IRepository public dlRepository;

    DataLayrPaymentChallengeFactory public dataLayrPaymentChallengeFactory;
    DataLayrDisclosureChallengeFactory public dataLayrDisclosureChallengeFactory;

    uint256 wethInitialSupply = 10e50;
    uint256 undelegationFraudProofInterval = 7 days;
    uint256 consensusLayerEthToEth = 10;
    uint256 timelockDelay = 2 days;
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
        eigen = new Eigen(ownerAddr);

        deposit = new EigenLayrDeposit(consensusLayerDepositRoot);
        //do stuff this eigen token here
        delegation = new EigenLayrDelegation();
        slasher = new Slasher(investmentManager);
        serviceFactory = new ServiceFactory(investmentManager, delegation);
        investmentManager = new InvestmentManager(eigen, delegation, serviceFactory);
        //used in the one investment strategy
        weth = new ERC20PresetFixedSupply(
            "weth",
            "WETH",
            wethInitialSupply,
            ownerAddr
        );
        //do stuff with weth
        strat = new WethStashInvestmentStrategy();
        strat.initialize(address(investmentManager), weth);

        IInvestmentStrategy[] memory strats = new IInvestmentStrategy[](1);
        strats[0] = IInvestmentStrategy(address(strat));

        address governor = address(this);
        investmentManager.initialize(
            strats,
            address(slasher),
            governor,
            address(deposit)
        );

        delegation.initialize(
            investmentManager,
            serviceFactory,
            undelegationFraudProofInterval
        );

        dataLayrPaymentChallengeFactory = new DataLayrPaymentChallengeFactory();
        dataLayrDisclosureChallengeFactory = new DataLayrDisclosureChallengeFactory();

        uint256 feePerBytePerTime = 1;
        dlsm = new DataLayrServiceManager(
            delegation,
            weth,
            weth,
            feePerBytePerTime,
            dataLayrPaymentChallengeFactory,
            dataLayrDisclosureChallengeFactory
        );
        dl = new DataLayr();

        dlRepository = new Repository();

        dlRegVW = new DataLayrVoteWeigher(Repository(address(dlRepository)), delegation, consensusLayerEthToEth);

        Repository(address(dlRepository)).initialize(
            dlRegVW,
            dlsm,
            dlRegVW,
            timelockDelay,
            delegation,
            investmentManager
        );

        dl.setRepository(dlRepository);
        dlsm.setRepository(dlRepository);
        dlsm.setDataLayr(dl);

        deposit.initialize(depositContract, investmentManager, dlsm);
    }
}