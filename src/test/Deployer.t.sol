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

import "../contracts/libraries/BytesLib.sol";
import "../contracts/utils/SignatureCompaction.sol";

import "./CheatCodes.sol";

contract EigenLayrDeployer is DSTest, ERC165_Universal, ERC1155TokenReceiver {
    using BytesLib for bytes;

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

    uint256 wethInitialSupply = 10e50;
    uint256 undelegationFraudProofInterval = 7 days;
    uint256 consensusLayerEthToEth = 10;
    uint256 timelockDelay = 2 days;
    bytes32 consensusLayerDepositRoot =
        0x9c4bad94539254189bb933df374b1c2eb9096913a1f6a3326b84133d2b9b9bad;
    address storer = address(420);
    address registrant = address(0x4206904396bF2f8b173350ADdEc5007A52664293); //sk: e88d9d864d5d731226020c5d2f02b62a4ce2a4534a39c225d32d3db795f83319

    //from testing seed phrase
    bytes32 priv_key_0 = 0x1234567812345678123456781234567812345678123456781234567812345678;
    address acct_0 = cheats.addr(uint256(priv_key_0));

    //performs basic deployment before each test
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

        investmentManager.initialize(
            strats,
            address(slasher),
            address(deposit)
        );

        delegation.initialize(
            investmentManager,
            serviceFactory,
            undelegationFraudProofInterval
        );

        uint256 feePerBytePerTime = 1;
        dlsm = new DataLayrServiceManager(
            delegation,
            weth,
            weth,
            feePerBytePerTime
        );
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
        assertTrue(
            address(depositContract) != address(0),
            "depositContract failed to deploy"
        );
        assertTrue(address(eigen) != address(0), "eigen failed to deploy");
        assertTrue(
            address(delegation) != address(0),
            "delegation failed to deploy"
        );
        assertTrue(
            address(investmentManager) != address(0),
            "investmentManager failed to deploy"
        );
        assertTrue(address(slasher) != address(0), "slasher failed to deploy");
        assertTrue(
            address(serviceFactory) != address(0),
            "serviceFactory failed to deploy"
        );
        assertTrue(address(weth) != address(0), "weth failed to deploy");
        assertTrue(address(dlsm) != address(0), "dlsm failed to deploy");
        assertTrue(address(dl) != address(0), "dl failed to deploy");
        assertTrue(address(dlRegVW) != address(0), "dlRegVW failed to deploy");
        assertTrue(address(dlqm) != address(0), "dlqm failed to deploy");
        assertTrue(address(deposit) != address(0), "deposit failed to deploy");
        assertTrue(dlqm.feeManager() == dlsm, "feeManager set incorrectly");
        assertTrue(
            dlsm.queryManager() == dlqm,
            "queryManager set incorrectly in dlsm"
        );
        assertTrue(
            dl.queryManager() == dlqm,
            "queryManager set incorrectly in dl"
        );
    }

    //verifies that depositing WETH works
    function testWethDeposit(
        uint256 amountToDeposit)
        public 
        returns (uint256 amountDeposited)
    {
        return _testWethDeposit(registrant, amountToDeposit);
    }

    //deposits 'amountToDeposit' of WETH from address 'sender'
    function _testWethDeposit(
        address sender,
        uint256 amountToDeposit)
        internal 
        returns (uint256 amountDeposited)
    {
        //trying to deposit more than the wethInitialSupply will fail, so in this case we expect a revert and return '0' if it happens
        if (amountToDeposit > wethInitialSupply) {
            cheats.expectRevert(
                bytes("ERC20: transfer amount exceeds balance")
            );

            weth.transfer(sender, amountToDeposit);
            amountDeposited = 0;
        } else {
            weth.transfer(sender, amountToDeposit);
            cheats.startPrank(sender);
            weth.approve(address(investmentManager), type(uint256).max);

            investmentManager.depositIntoStrategy(
                sender,
                strat,
                weth,
                amountToDeposit
            );
            amountDeposited = amountToDeposit;
        }
        //in this case, since shares never grow, the shares should just match the deposited amount
        assertEq(
            investmentManager.investorStratShares(sender, strat),
            amountDeposited,
            "shares should match deposit"
        );
        cheats.stopPrank();
    }

    //checks that it is possible to withdraw WETH
    function testWethWithdrawal(
        uint256 amountToDeposit,
        uint256 amountToWithdraw
    ) public {
        _testWethWithdrawal(registrant, amountToDeposit, amountToWithdraw);
    }

    //checks that it is possible to withdraw WETH
    function _testWethWithdrawal(
        address sender,
        uint256 amountToDeposit,
        uint256 amountToWithdraw
    ) internal {
        uint256 amountDeposited = _testWethDeposit(sender, amountToDeposit);
        cheats.prank(sender);

        //if amountDeposited is 0, then trying to withdraw will revert. expect a revert and short-circuit if it happens
        //TODO: figure out if making this 'expectRevert' work correctly is actually possible
        if (amountDeposited == 0) {
            // cheats.expectRevert(bytes("Index out of bounds."));
            // investmentManager.withdrawFromStrategy(0, strat, weth, amountToWithdraw);
            return;
            //trying to withdraw more than the amountDeposited will fail, so we expect a revert and short-circuit if it happens
        } else if (amountToWithdraw > amountDeposited) {
            cheats.expectRevert(bytes("shareAmount too high"));
            investmentManager.withdrawFromStrategy(
                0,
                strat,
                weth,
                amountToWithdraw
            );
            return;
        } else {
            investmentManager.withdrawFromStrategy(
                0,
                strat,
                weth,
                amountToWithdraw
            );
        }
        uint256 wethBalanceAfter = weth.balanceOf(sender);

        assertEq(
            amountToDeposit - amountDeposited + amountToWithdraw,
            wethBalanceAfter,
            "weth is missing somewhere"
        );
        cheats.stopPrank();
    }

    //checks that it is possible to prove a consensus layer deposit
    function testCleProof() public {
        address depositor = address(0x1234123412341234123412341234123412341235);
        uint256 amount = 100;
        bytes32[] memory proof = new bytes32[](3);
        proof[0] = bytes32(
            0x0c70933f97e33ce23514f82854b7000db6f226a3c6dd2cf42894ce71c9bb9e8b
        );
        proof[1] = bytes32(
            0x200634f4269b301e098769ce7fd466ca8259daad3965b977c69ca5e2330796e1
        );
        proof[2] = bytes32(
            0x1944162db3ee014776b5da7dbb53c9d7b9b11b620267f3ea64a7f46a5edb403b
        );
        cheats.prank(depositor);
        deposit.proveLegacyConsensusLayerDeposit(
            proof,
            address(0),
            "0x",
            amount
        );
        //make sure their cle has updated
        assertEq(investmentManager.consensusLayerEth(depositor), amount);
    }

    //checks that it is possible to init a data store
    function testInitDataStore() public returns (bytes32) {
        return _testInitDataStore();
    }

    //initiates a data store
    //checks that the dumpNumber, initTime, storePeriodLength, and committed status are all correct
    function _testInitDataStore() internal returns (bytes32) {
        bytes memory header = bytes(
            "0x0102030405060708091011121314151617181920"
        );
        uint32 totalBytes = 1e6;
        uint32 storePeriodLength = 600;

        //weth is set as the paymentToken of dlsm, so we must approve dlsm to transfer weth
        weth.transfer(storer, 10e10);
        cheats.prank(storer);
        weth.approve(address(dlsm), type(uint256).max);
        cheats.prank(storer);
        DataLayrServiceManager(address(dlqm)).initDataStore(
            storer,
            header,
            totalBytes,
            storePeriodLength
        );
        uint48 dumpNumber = 1;
        bytes32 headerHash = keccak256(header);
        (
            uint48 dataStoreDumpNumber,
            uint32 dataStoreInitTime,
            uint32 dataStorePeriodLength,
            bool dataStoreCommitted
        ) = dl.dataStores(headerHash);
        assertTrue(dataStoreDumpNumber == dumpNumber, "_testInitDataStore: wrong dumpNumber");
        assertTrue(
            dataStoreInitTime == uint32(block.timestamp),
            "_testInitDataStore: wrong initTime"
        );
        assertTrue(
            dataStorePeriodLength == storePeriodLength,
            "_testInitDataStore: wrong storePeriodLength"
        );
        assertTrue(dataStoreCommitted == false, "_testInitDataStore: wrong committed status");
        return headerHash;
    }   

    //verifies that it is possible to confirm a data store
    //checks that the store is marked as committed
    function testConfirmDataStore() public {
        bytes memory stakes = testSelfOperatorRegister();
        // emit log_named_bytes("stakes is now", stakes);
        bytes32 headerHash = _testInitDataStore();

        uint48 dumpNumber = 1;
        uint32 numberOfSigners = 1;
        uint256 stakesIndex = 1;
        cheats.prank(storer);
        bytes memory data = abi.encodePacked(
            dumpNumber,
            headerHash,
            numberOfSigners,
            stakesIndex,
            uint256(stakes.length)
        );
        data = abi.encodePacked(
            data,
            stakes,
            //signature r
            bytes32(
                0xd014256b124b583eb14192505340f3c785c31c3412c7daa358072c0b81b85aa5
            ),
            //signature vs
            bytes32(
                0xf4c6a5d675588f311a9061cf6cbf6eacd95a15f42c9d111a9f65767dfe2e6ff8
            ),
            //index in stakes object
            uint32(0)
        );
         emit log_named_uint("gas before, testConfirmDataStore()", gasleft());

        DataLayrServiceManager(address(dlqm)).confirmDataStore(storer, data);

         emit log_named_uint("gas after, testConfirmDataStore()", gasleft());

        //(uint48 dumpNumber, uint32 initTime, uint32 spl, bool committed) = dl.dataStores(headerHash);
        (, , , bool committed) = dl.dataStores(headerHash);
        assertTrue(committed, "Data store not committed");
    }

    //verifies that it is possible to deposit eigen
    function testDepositEigen() public {
        _testDepositEigen(registrant);
    }

    //deposits a fixed amount of eigen from address 'sender'
    //checks that the deposit is credited correctly
    function _testDepositEigen(address sender) public {
        uint256 toDeposit = 1e17;
        eigen.safeTransferFrom(address(this), sender, 0, toDeposit, "0x");
        cheats.startPrank(sender);
        eigen.setApprovalForAll(address(deposit), true);

        deposit.depositEigen(toDeposit);

        assertEq(
            investmentManager.eigenDeposited(sender),
            toDeposit,
            "_testDepositEigen: deposit not properly credited"
        );
        cheats.stopPrank();
    }

    function testSelfOperatorDelegate() public {
        _testSelfOperatorDelegate(registrant);
    }

    function _testSelfOperatorDelegate(address sender) internal {
        cheats.prank(sender);
        delegation.delegateToSelf();
        assertTrue(
            delegation.delegation(sender) == sender,
            "_testSelfOperatorDelegate: self delegation not properly recorded"
        );
        assertTrue(
            delegation.delegated(sender),
            "_testSelfOperatorDelegate: delegation not credited?"
        );
    }

    function testSelfOperatorRegister()
        public
        returns (bytes memory)
    {
        //register as both ETH and EIGEN operator
        uint8 registrantType = 3;
        uint256 stakesLength = 24;
        // emptyStakes is used in place of stakes, since right now they are empty (two totals of 12 zero bytes each)
        bytes24 emptyStakes = bytes24(0);
        uint8 socketLength = 1;
        bytes memory socket = "ff";
        bytes memory data = abi.encodePacked(
            registrantType,
            stakesLength,
            emptyStakes,
            socketLength,
            socket
        );

        return _testSelfOperatorRegister(registrant, data);
    }

    function _testSelfOperatorRegister(address sender, bytes memory data)
        internal
        returns (bytes memory)
    {
        _testWethDeposit(sender, 1e18);
        _testDepositEigen(sender);
        _testSelfOperatorDelegate(sender);

        cheats.startPrank(sender);
        dlqm.register(data);

        uint48 dumpNumber = dlRegVW.stakeHashUpdates(dlRegVW.getStakesHashUpdateLength() - 1);
        // emit log_named_uint("dumpNumber", dumpNumber);
        uint128 weightOfOperatorEth = dlRegVW.weightOfOperatorEth(sender);
        uint128 weightOfOperatorEigen = dlRegVW.weightOfOperatorEigen(sender);
        bytes memory stakes = abi.encodePacked(
            sender,
            uint96(weightOfOperatorEth),
            uint96(weightOfOperatorEigen),
            uint96(weightOfOperatorEth),
            uint96(weightOfOperatorEigen)
        );
        bytes32 hashOfStakes = keccak256(stakes);
        assertTrue(
            hashOfStakes == dlRegVW.stakeHashes(dumpNumber),
            "_testSelfOperatorRegister: stakes stored incorrectly"
        );

        cheats.stopPrank();
        return (stakes);
    }

    function testTwoSelfOperatorsRegister() internal returns (bytes memory)
    {
        (bytes memory stakesPrev) = testSelfOperatorRegister();
        address sender = acct_0;
        return _testRegisterAdditionalSelfOperator(sender, stakesPrev);
    }

    function _testRegisterAdditionalSelfOperator(address sender, bytes memory stakesPrev) internal returns (bytes memory) {
        //register as both ETH and EIGEN operator
        uint8 registrantType = 3;
        _testWethDeposit(sender, 1e18);
        _testDepositEigen(sender);
        _testSelfOperatorDelegate(sender);  
        bytes memory socket = "fe";
        bytes memory data = abi.encodePacked(
            registrantType,
            uint256(stakesPrev.length),
            stakesPrev,
            uint8(socket.length),
            socket
        );

        cheats.startPrank(sender);
        dlqm.register(data);

        uint48 dumpNumber = dlRegVW.stakeHashUpdates(dlRegVW.getStakesHashUpdateLength() - 1);

        uint128 weightOfOperatorEth = dlRegVW.weightOfOperatorEth(sender);
        uint128 weightOfOperatorEigen = dlRegVW.weightOfOperatorEigen(sender);
        bytes memory stakes = abi.encodePacked(
            stakesPrev.slice(0,stakesPrev.length - 24),
            registrantType,
            sender,
            weightOfOperatorEth,
            weightOfOperatorEigen,
            uint96(weightOfOperatorEth) + (stakesPrev.toUint96(stakesPrev.length - 24)),
            uint96(weightOfOperatorEigen) + (stakesPrev.toUint96(stakesPrev.length - 12))
        );
        bytes32 hashOfStakes = keccak256(stakes);
        assertTrue(
            hashOfStakes == dlRegVW.stakeHashes(dumpNumber),
            "_testRegisterAdditionalSelfOperator: stakes stored incorrectly"
        );

        cheats.stopPrank();
        return (stakes);
    }

    function testConfirmDataStoreTwoOperators() public {
        bytes memory stakes = testTwoSelfOperatorsRegister();

        bytes32 headerHash = _testInitDataStore();

        bytes32 signedHash = ECDSA.toEthSignedMessageHash(headerHash);
        // bytes32 signedHash = headerHash;

        (uint8 v, bytes32 r, bytes32 s) = cheats.sign(uint256(priv_key_0), signedHash);
        bytes32 vs = SignatureCompaction.packVS(s,v);

        require(ecrecover(signedHash, v, r, s) == acct_0, "bad sign");

        uint32 numberOfSigners = 2;

        // uint48 dumpNumberAtIndex = dlRegVW.stakeHashUpdates(dlRegVW.getStakesHashUpdateLength() - 1);
        uint48 currentDumpNumber = dlsm.dumpNumber();

        bytes memory data = abi.encodePacked(
            // uint48(dataStoreDumpNumber),
            // uint48(2),
            currentDumpNumber,
            headerHash,
            numberOfSigners,
            uint256(dlRegVW.getStakesHashUpdateLength() - 1)
        );
        data = abi.encodePacked(
            data,
            stakes.length,
            stakes
        );
        data = abi.encodePacked(
            data,
            bytes32(
                0xd014256b124b583eb14192505340f3c785c31c3412c7daa358072c0b81b85aa5
            ),
            bytes32(
                0xf4c6a5d675588f311a9061cf6cbf6eacd95a15f42c9d111a9f65767dfe2e6ff8
            ),
            uint32(0) //signatory's index in stakes object
        );
        data = abi.encodePacked(
            data,
            r,
            vs,
            uint32(1) //signatory's index in stakes object
        );

        cheats.prank(storer);

         emit log_named_uint("gas before, testConfirmDataStoreTwoOperators()", gasleft());

        DataLayrServiceManager(address(dlqm)).confirmDataStore(storer, data);

         emit log_named_uint("gas after, testConfirmDataStoreTwoOperators()", gasleft());
        (, , ,bool committed) = dl.dataStores(headerHash);
        assertTrue(committed, "Data store not committed");
        cheats.stopPrank();

    }
}