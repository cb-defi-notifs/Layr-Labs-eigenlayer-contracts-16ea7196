// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./mocks/DepositContract.sol";
import "../contracts/governance/Timelock.sol";

import "../contracts/core/Eigen.sol";

import "../contracts/core/EigenLayrDelegation.sol";
import "../contracts/core/EigenLayrDeposit.sol";

import "../contracts/investment/InvestmentManager.sol";
import "../contracts/investment/WethStashInvestmentStrategy.sol";
import "../contracts/investment/Slasher.sol";

import "../contracts/middleware/ServiceFactory.sol";
import "../contracts/middleware/QueryManager.sol";
import "../contracts/middleware/DataLayr/DataLayr.sol";
import "../contracts/middleware/DataLayr/DataLayrServiceManager.sol";
import "../contracts/middleware/DataLayr/DataLayrVoteWeigher.sol";

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";


import "ds-test/test.sol";

contract EigenLayrDeployer is DSTest {
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
    IQueryManager public dlqm;

    constructor(
        uint256 wethInitialSupply,
        uint256 undelegationFraudProofInterval,
        bytes32 consensusLayerDepositRoot,
        uint256 consensusLayerEthToEth,
        uint256 timelockDelay
    ) {
        //eth2 deposit contract
        depositContract = new DepositContract();
        //deploy eigen
        eigen = new Eigen(address(this));
        //do stuff this eigen token here
        delegation = new EigenLayrDelegation();
        investmentManager = new InvestmentManager(eigen, delegation);
        slasher = new Slasher(investmentManager);
        serviceFactory = new ServiceFactory(investmentManager);
        //used in the one investment strategy
        weth = new ERC20PresetFixedSupply(
            "weth",
            "WETH",
            wethInitialSupply,
            address(this)
        );
        //do stuff with weth
        strat = new WethStashInvestmentStrategy();
        strat.initialize(address(investmentManager), weth);

        IInvestmentStrategy[] memory strats = new IInvestmentStrategy[](1);
        strats[0] = IInvestmentStrategy(address(strat));

        investmentManager.initialize(strats, address(slasher));

        delegation.initialize(
            investmentManager,
            serviceFactory,
            undelegationFraudProofInterval
        );

        dlsm = new DataLayrServiceManager(delegation, weth, weth);
        dl = new DataLayr(address(dlsm));
        dlRegVW = new DataLayrVoteWeigher(investmentManager, delegation);

        dlqm = serviceFactory.createNewQueryManager(
            1 days,
            consensusLayerEthToEth,
            dlsm,
            dlRegVW,
            dlRegVW,
            timelockDelay,
            delegation
        );

        dlsm.setDataLayr(dl);
        dlsm.setQueryManager(dlqm);
        dlRegVW.setQueryManager(dlqm);

        deposit = new EigenLayrDeposit(consensusLayerDepositRoot, eigen);
        deposit.initialize(depositContract, investmentManager, dlsm);

        // deposit.initialize()
    }

    function setUp() public
    {
        uint256 wethInitialSupply = 10e18;
        uint256 undelegationFraudProofInterval = 7 days;
        bytes32 consensusLayerDepositRoot;
        uint256 consensusLayerEthToEth = 10;
        uint256 timelockDelay = 600;


        //eth2 deposit contract
        depositContract = new DepositContract();
        //deploy eigen
        eigen = new Eigen(address(this));
        //do stuff this eigen token here
        delegation = new EigenLayrDelegation();
        investmentManager = new InvestmentManager(eigen, delegation);
        slasher = new Slasher(investmentManager);
        serviceFactory = new ServiceFactory(investmentManager);
        //used in the one investment strategy
        weth = new ERC20PresetFixedSupply(
            "weth",
            "WETH",
            wethInitialSupply,
            address(this)
        );
        //do stuff with weth
        strat = new WethStashInvestmentStrategy();
        strat.initialize(address(investmentManager), weth);

        IInvestmentStrategy[] memory strats = new IInvestmentStrategy[](1);
        strats[0] = IInvestmentStrategy(address(strat));

        investmentManager.initialize(strats, address(slasher));

        delegation.initialize(
            investmentManager,
            serviceFactory,
            undelegationFraudProofInterval
        );

        dlsm = new DataLayrServiceManager(delegation, weth, weth);
        dl = new DataLayr(address(dlsm));
        dlRegVW = new DataLayrVoteWeigher(investmentManager, delegation);

        dlqm = serviceFactory.createNewQueryManager(
            1 days,
            consensusLayerEthToEth,
            dlsm,
            dlRegVW,
            dlRegVW,
            timelockDelay,
            delegation
        );

        dlsm.setDataLayr(dl);
        dlsm.setQueryManager(dlqm);
        dlRegVW.setQueryManager(dlqm);

        deposit = new EigenLayrDeposit(consensusLayerDepositRoot, eigen);
        deposit.initialize(depositContract, investmentManager, dlsm);

        // deposit.initialize()
    }

    function testBroken() public {
        assertTrue(1 == 0);
    }

    function testDeploymentSuccessful() public {
        assertTrue(address(deposit) == address(0), "test should fail here");
        assertTrue(address(depositContract) != address(0), "depositContract failed to deploy");
        assertTrue(address(eigen) != address(0), "eigen failed to deploy");
        assertTrue(address(delegation) != address(0), "delegation failed to deploy");
        assertTrue(address(investmentManager) != address(0), "investmentManager failed to deploy");
        assertTrue(address(slasher) != address(0), "slasher failed to deploy");
        assertTrue(address(serviceFactory) != address(0), "serviceFactory failed to deploy");
        assertTrue(address(weth) != address(0), "weth failed to deploy");
        assertTrue(address(dlsm) != address(0), "dlsm failed to deploy");
        assertTrue(address(dl) != address(0), "dl failed to deploy");
        assertTrue(address(dlRegVW) != address(0), "dlRegVW failed to deploy");
        assertTrue(address(dlqm) != address(0), "dlqm failed to deploy");
        assertTrue(address(deposit) != address(0), "deposit failed to deploy");
        assertTrue(1 == 0, "test should fail here also");
    }
}
