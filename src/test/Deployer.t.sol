// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "ds-test/test.sol";

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

    function setUp() public {}

    function testSetUp() public {
        //eth2 deposit contract
        depositContract = new DepositContract();
        //deploy eigen
        eigen = new Eigen();
        //do stuff this eigen token here
        delegation = new EigenLayrDelegation();
        investmentManager = new InvestmentManager(eigen, delegation);
        slasher = new Slasher(investmentManager);
        serviceFactory = new ServiceFactory(investmentManager);
        //used in the one investment strategy
        IERC20 weth = new ERC20PresetFixedSupply(
            "weth",
            "WETH",
            100, //wethInitialSupply,
            address(this)
        );
        //do stuff with weth
        WethStashInvestmentStrategy strat = new WethStashInvestmentStrategy();
        strat.initialize(address(investmentManager), weth);

        IInvestmentStrategy[] memory strats = new IInvestmentStrategy[](1);
        strats[0] = IInvestmentStrategy(address(strat));

        investmentManager.initialize(strats, address(slasher));

        delegation.initialize(
            investmentManager,
            serviceFactory,
            7 days //undelegationFraudProofInterval
        );

        dlsm = new DataLayrServiceManager(delegation, weth, weth);
        dl = new DataLayr(address(dlsm));
        dlRegVW = new DataLayrVoteWeigher(investmentManager, delegation);

        IQueryManager dlqm = serviceFactory.createNewQueryManager(
            1 days,
            10, //consensusLayerEthToEth,
            dlsm,
            dlRegVW,
            dlRegVW,
            10 days, //timelockDelay,
            delegation
        );

        dlsm.setDataLayr(dl);
        dlsm.setQueryManager(dlqm);
        dlRegVW.setQueryManager(dlqm);

        deposit = new EigenLayrDeposit(
            bytes32(0), //consensusLayerDepositRoot, 
            eigen);
        deposit.initialize(depositContract, investmentManager, dlsm);

        // deposit.initialize()
    }
}
