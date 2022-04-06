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

    uint256 wethInitialSupply = 10e50;
    uint256 undelegationFraudProofInterval = 7 days;
    uint256 consensusLayerEthToEth = 10;
    uint256 timelockDelay = 2 days;
    bytes32 consensusLayerDepositRoot =
        0x9c4bad94539254189bb933df374b1c2eb9096913a1f6a3326b84133d2b9b9bad;
    address storer = address(420);
    address registrant = address(0x4206904396bF2f8b173350ADdEc5007A52664293); //sk: e88d9d864d5d731226020c5d2f02b62a4ce2a4534a39c225d32d3db795f83319

    //from testing seed phrase
    bytes32 priv_key_0 = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address acct_0 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

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

    function testWethDeposit(
        uint256 amountToDeposit)
        public 
        returns (uint256 amountDeposited)
    {
        _testWethDeposit(registrant, amountToDeposit);
    }

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

    function testWethWithdrawal(
        uint256 amountToDeposit,
        uint256 amountToWithdraw
    ) public {
        _testWethWithdrawal(registrant, amountToDeposit, amountToWithdraw);
    }

    function _testWethWithdrawal(
        address sender,
        uint256 amountToDeposit,
        uint256 amountToWithdraw
    ) internal {
        uint256 amountDeposited = _testWethDeposit(sender, amountToDeposit);
        cheats.prank(sender);
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

    function testInitDataStore() public returns (bytes32) {
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
        assertTrue(dataStoreDumpNumber == dumpNumber, "wrong dumpNumber");
        assertTrue(
            dataStoreInitTime == uint32(block.timestamp),
            "wrong initTime"
        );
        assertTrue(
            dataStorePeriodLength == storePeriodLength,
            "wrong storePeriodLength"
        );
        assertTrue(dataStoreCommitted == false, "wrong committed status");
        return headerHash;
    }

    function testConfirmDataStore() public {
        (
            bytes memory ethStakes,
            bytes memory eigenStakes
        ) = testSelfOperatorRegister();
        bytes32 headerHash = testInitDataStore();
        // uint48 dumpNumber,
        // bytes32 headerHash,
        // uint32 numberOfSigners,
        // uint256 ethStakesIndex, uint256 eigenStakesIndex,
        // uint256 ethStakesLength, uint256 eigenStakesLength,
        // bytes ethStakes, bytes eigenStakes,
        // bytes sigWInfos (number of sigWInfos provided here is equal to numberOfSigners)

        // ethStakes layout:
        // packed uint128, one for each signatory that is an ETH signatory (signaled by setting stakerType % 2 == 0)

        // eigenStakes layout:
        // packed uint128, one for each signatory that is an EIGEN signatory (signaled by setting stakerType % 3 == 0)

        // sigWInfo layout:
        // bytes32 r
        // bytes32 vs
        // bytes1 stakerType
        // if (sigWInfo.stakerType % 2 == 0) {
        //     uint32 ethStakesIndex of signatory
        // }
        // if (sigWInfo.stakerType % 3 == 0) {
        //     uint32 eigenStakesIndex of signatory
        // }

        // indexes aare 1 becuase both hashes have only been updated once
        // length is known because only 1 staker so 20 + 16 + 32 = 68
        // precomputed signature and we know they are eth and eigen
        // all arguments will be computed off chain
        // ConfirmCalldata memory data;
        // data.dumpNumber = 1;
        // data.headerHash = headerHash;
        // data.numberOfSigners = 1;
        // data.ethStakesIndex = 1;
        // data.eigenStakesIndex = 1;
        // data.ethStakesLength = 68;
        // data.eigenStakesLength = 68;
        // data.ethStakes = ethStakes;
        // data.eigenStakes = eigenStakes;
        // data.sigWInfos = abi.encodePacked(
        //     bytes32(
        //         0xdfb9b0b03bd42ddcea0a5e0e4878440c2437aa77094c2d234d5934b1a21a01ef
        //     ),
        //     bytes32(
        //         0xF0875e533676b8e11d4138de62a20f5d49a20a3501e54d6a67bd64fe4d5a8560
        //     ),
        //     uint8(0)
        // );
        cheats.prank(storer);
        bytes memory data = abi.encodePacked(
            uint48(1),
            headerHash,
            uint32(1),
            uint256(1),
            uint256(1),
            uint256(68),
            uint256(68)
        );
        data = abi.encodePacked(
            data,
            ethStakes,
            eigenStakes,
            bytes32(
                0xd014256b124b583eb14192505340f3c785c31c3412c7daa358072c0b81b85aa5
            ),
            bytes32(
                0xf4c6a5d675588f311a9061cf6cbf6eacd95a15f42c9d111a9f65767dfe2e6ff8
            ),
            uint8(0),
            uint32(0),
            uint32(0)
        );
        emit log_named_uint("3", gasleft());

        DataLayrServiceManager(address(dlqm)).confirmDataStore(storer, data);

        emit log_named_uint("3", gasleft());

        (uint48 dumpNumber, uint32 initTime, uint32 spl,bool commited) = dl.dataStores(headerHash);
        assertTrue(commited, "Data store not commited");
    }

    function testDepositEigen() public {
        _testDepositEigen(registrant);
    }

    function _testDepositEigen(address sender) public {
        //approve 'deposit' contract to transfer EIGEN on behalf of this contract
        uint256 toDeposit = 1e18;
        eigen.safeTransferFrom(address(this), sender, 0, toDeposit, "0x");
        cheats.startPrank(sender);
        eigen.setApprovalForAll(address(deposit), true);

        deposit.depositEigen(toDeposit);

        assertEq(
            investmentManager.eigenDeposited(sender),
            toDeposit,
            "deposit not properly credited"
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
            "self delegation not properly recorded"
        );
        assertTrue(
            delegation.delegated(sender),
            "delegation not credited?"
        );
    }

    function testSelfOperatorRegister()
        public
        returns (bytes memory, bytes memory)
    {
        return _testSelfOperatorRegister(registrant);
    }

    function _testSelfOperatorRegister(address sender)
        internal
        returns (bytes memory, bytes memory)
    {
        //first byte of data is operator type

        _testWethDeposit(sender, 1e18);
        _testDepositEigen(sender);
        _testSelfOperatorDelegate(sender);

        //register as both ETH and EIGEN operator
        // uint8 registrantType = 3;
        //spacer is used in place of stake totals
        // bytes32 spacer = bytes32(0);
        // uint256 ethStakesLength = 32;
        // uint256 eigenStakesLength = 32;
        bytes memory data = abi.encodePacked(
            uint8(3),
            uint256(32),
            bytes32(0),
            uint256(32),
            bytes32(0),
            uint8(1),
            bytes("ff")
        );
        cheats.startPrank(sender);
        dlqm.register(data);

        uint48 dumpNumber = dlRegVW.ethStakeHashUpdates(1);

        uint128 weightOfOperatorEth = dlRegVW.weightOfOperatorEth(sender);
        bytes memory ethStakes = abi.encodePacked(
            sender,
            weightOfOperatorEth,
            uint256(weightOfOperatorEth)
        );
        bytes32 hashOfStakesEth = keccak256(ethStakes);
        assertTrue(
            hashOfStakesEth == dlRegVW.ethStakeHashes(dumpNumber),
            "ETH stakes stored incorrectly"
        );

        uint128 weightOfOperatorEigen = dlRegVW.weightOfOperatorEigen(
            sender
        );
        bytes memory eigenStakes = abi.encodePacked(
            sender,
            weightOfOperatorEigen,
            uint256(weightOfOperatorEigen)
        );
        bytes32 hashOfStakesEigen = keccak256(eigenStakes);
        assertTrue(
            hashOfStakesEigen == dlRegVW.eigenStakeHashes(dumpNumber),
            "EIGEN stakes stored incorrectly"
        );
        cheats.stopPrank();
        return (ethStakes, eigenStakes);
    }
}
