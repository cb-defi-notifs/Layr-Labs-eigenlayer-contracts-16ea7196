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

import "../contracts/interfaces/ERC165_Universal.sol";

interface CheatCodes {
    function prank(address) external;
}

contract EigenLayrDeployer is DSTest, ERC165_Universal {
    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);
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

    uint256 wethInitialSupply = 10e18;
    uint256 undelegationFraudProofInterval = 7 days;
    uint256 consensusLayerEthToEth = 10;
    uint256 timelockDelay = 2 days;
    bytes32 consensusLayerDepositRoot = 0x9c4bad94539254189bb933df374b1c2eb9096913a1f6a3326b84133d2b9b9bad;

    function setUp() public {
        //eth2 deposit contract
        depositContract = new DepositContract();
        //deploy eigen. send eigen tokens to an address where they won't trigger failure for 'transfer to non ERC1155Receiver implementer,'
        eigen = new Eigen(address(37));

        deposit = new EigenLayrDeposit(consensusLayerDepositRoot, eigen);
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

        investmentManager.initialize(strats, address(slasher), address(deposit));

        delegation.initialize(
            investmentManager,
            serviceFactory,
            undelegationFraudProofInterval
        );

        dlsm = new DataLayrServiceManager(delegation, weth, weth);
        dl = new DataLayr();
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

        dlsm.setQueryManager(dlqm);
        dlsm.setDataLayr(dl);
        dlRegVW.setQueryManager(dlqm);

        deposit.initialize(depositContract, investmentManager, dlsm);
    }

    function testDeploymentSuccessful() public {
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
    }

    function testWethDeposit() public {
        weth.approve(address(investmentManager), type(uint256).max);
        investmentManager.depositIntoStrategy(address(this), strat, weth, wethInitialSupply);
    }

    function testCleProof() public {
        address depositor = address(0x1234123412341234123412341234123412341235);
        uint256 amount = 100;
        bytes32[] memory proof = new bytes32[](3);
        proof[0] = bytes32(0x0c70933f97e33ce23514f82854b7000db6f226a3c6dd2cf42894ce71c9bb9e8b);
        proof[1] = bytes32(0x200634f4269b301e098769ce7fd466ca8259daad3965b977c69ca5e2330796e1);
        proof[2] = bytes32(0x1944162db3ee014776b5da7dbb53c9d7b9b11b620267f3ea64a7f46a5edb403b);
        cheats.prank(depositor);
        deposit.proveLegacyConsensusLayerDeposit(proof, address(0), "0x", amount);
        //make sure their cle has updated
        assertEq(investmentManager.consensusLayerEth(depositor), amount);
    }
}
