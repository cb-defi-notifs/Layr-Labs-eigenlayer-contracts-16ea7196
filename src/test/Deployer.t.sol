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

import "../contracts/utils/ERC165_Universal.sol";
import "../contracts/utils/ERC1155TokenReceiver.sol";

import "./CheatCodes.sol";

contract EigenLayrDeployer is DSTest, ERC165_Universal, ERC1155TokenReceiver {
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
        eigen = new Eigen(address(this));

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

        uint256 feePerBytePerTime = 1e4;
        dlsm = new DataLayrServiceManager(delegation, weth, weth, feePerBytePerTime);
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

        dl.setQueryManager(dlqm);
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
        assertTrue(dlqm.feeManager() == dlsm, "feeManager set incorrectly");
        assertTrue(dlsm.queryManager() == dlqm, "queryManager set incorrectly in dlsm");
        assertTrue(dl.queryManager() == dlqm, "queryManager set incorrectly in dl");
    }

    function testWethDeposit(uint256 amountToDeposit) public returns(uint256 amountDeposited) {
        weth.approve(address(investmentManager), type(uint256).max);

        //trying to deposit more than the wethInitialSupply will fail, so in this case we expect a revert and return '0' if it happens
        if (amountToDeposit > wethInitialSupply) {
            cheats.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
            investmentManager.depositIntoStrategy(address(this), strat, weth, amountToDeposit);
            amountDeposited = 0;
        } else {
            investmentManager.depositIntoStrategy(address(this), strat, weth, amountToDeposit);
            amountDeposited = amountToDeposit;
        }

        //in this case, since shares never grow, the shares should just match the deposited amount
        assertEq(investmentManager.investorStratShares(address(this), strat), amountDeposited, "shares should match deposit");
    }

    function testWethWithdrawal(uint256 amountToDeposit, uint256 amountToWithdraw) public {
        uint256 wethBalanceBefore = weth.balanceOf(address(this));
        uint256 amountDeposited = testWethDeposit(amountToDeposit);

        // emit log_uint(amountToDeposit);
        // emit log_uint(amountToWithdraw);
        // emit log_uint(amountDeposited);

        //if amountDeposited is 0, then trying to withdraw will revert. expect a revert and short-circuit if it happens
        //TODO: figure out if making this 'expectRevert' work correctly is actually possible
        if (amountDeposited == 0) {
            // cheats.expectRevert(bytes("Index out of bounds."));
            // investmentManager.withdrawFromStrategy(0, strat, weth, amountToWithdraw);
            return;
        //trying to withdraw more than the amountDeposited will fail, so we expect a revert and short-circuit if it happens
        } else if (amountToWithdraw > amountDeposited) {
            cheats.expectRevert(bytes("shareAmount too high"));
            investmentManager.withdrawFromStrategy(0, strat, weth, amountToWithdraw);
            return;
        } else {
            investmentManager.withdrawFromStrategy(0, strat, weth, amountToWithdraw);
        }

        uint256 wethBalanceAfter = weth.balanceOf(address(this));
        assertEq(wethBalanceBefore - amountToDeposit + amountToWithdraw, wethBalanceAfter, "weth is missing somewhere");
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
        //make sure their cle has updates
        assertEq(investmentManager.consensusLayerEth(depositor), amount);
    }

    function testInitDataStore() public {
        bytes memory header = bytes("0x0102030405060708091011121314151617181920");
        uint32 totalBytes = 1e6;
        uint32 storePeriodLength = 600;

        //weth is set as the paymentToken of dlsm, so we must approve dlsm to transfer weth
        weth.approve(address(dlsm), type(uint256).max);

        DataLayrServiceManager(address(dlqm)).initDataStore(address(this), header, totalBytes, storePeriodLength);

        uint48 dumpNumber = 1;
        bytes32 ferkleRoot = keccak256(header);
        (uint48 dataStoreDumpNumber, uint32 dataStoreInitTime, uint32 dataStorePeriodLength, bool dataStoreCommitted) = dl.dataStores(ferkleRoot);
        assertTrue(dataStoreDumpNumber == dumpNumber, "wrong dumpNumber");
        assertTrue(dataStoreInitTime == uint32(block.timestamp), "wrong initTime");
        assertTrue(dataStorePeriodLength == storePeriodLength, "wrong storePeriodLength");
        assertTrue(dataStoreCommitted == false, "wrong committed status");
    }

    function testDepositEigen() public {

    }

    function testSelfOperatorSignup() public {
        //first byte of data is operator type
        //see 'registerOperator' function in 'DataLayrVoteWeigher'
        //TODO: format this data

        //register as both ETH and EIGEN operator
        uint8 registrantType = 3;
        bytes32 spacer;
        uint256 ethStakesLength = 0;
        uint256 eigenStakesLength = 0;
        bytes memory data = abi.encodePacked(registrantType,spacer,spacer,ethStakesLength,eigenStakesLength);
        dlqm.register(data);
    }
}
