// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./mocks/DepositContract.sol";
import "../contracts/governance/Timelock.sol";

import "../contracts/core/Eigen.sol";

import "../contracts/interfaces/IEigenLayrDelegation.sol";
import "../contracts/core/EigenLayrDelegation.sol";
import "../contracts/core/EigenLayrDeposit.sol";
import "../contracts/core/DelegationTerms.sol";

import "../contracts/investment/InvestmentManager.sol";
import "../contracts/investment/WethStashInvestmentStrategy.sol";
import "../contracts/investment/Slasher.sol";

import "../contracts/middleware/ServiceFactory.sol";
import "../contracts/middleware/Repository.sol";
import "../contracts/middleware/DataLayr/DataLayr.sol";
import "../contracts/middleware/DataLayr/DataLayrServiceManager.sol";
import "../contracts/middleware/DataLayr/DataLayrVoteWeigher.sol";
import "../contracts/middleware/DataLayr/DataLayrPaymentChallengeFactory.sol";
import "../contracts/middleware/DataLayr/DataLayrDisclosureChallengeFactory.sol";

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "ds-test/test.sol";

import "../contracts/utils/ERC165_Universal.sol";
import "../contracts/utils/ERC1155TokenReceiver.sol";

import "../contracts/libraries/BytesLib.sol";
import "../contracts/libraries/SignatureCompaction.sol";

import "./CheatCodes.sol";
import "./Signers.sol";

//TODO: encode data properly so that we initialize TransparentUpgradeableProxy contracts in their constructor rather than a separate call (if possible)
contract EigenLayrDeployer is DSTest, ERC165_Universal, ERC1155TokenReceiver, Signers {
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
    IRepository public dlRepository;

    ProxyAdmin public eigenLayrProxyAdmin;

    DataLayrPaymentChallengeFactory public dataLayrPaymentChallengeFactory;
    DataLayrDisclosureChallengeFactory public dataLayrDisclosureChallengeFactory;

    // strategy index => IInvestmentStrategy
    mapping(uint256 => IInvestmentStrategy) public strategies;
    // number of strategies deployed
    uint256 public numberOfStrats;

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

    bytes32 priv_key_1 = 0x1234567812345678123456781234567812345698123456781234567812348976;
    address acct_1 = cheats.addr(uint256(priv_key_1));



    //performs basic deployment before each test
    function setUp() public  {
        eigenLayrProxyAdmin = new ProxyAdmin();

        //eth2 deposit contract
        depositContract = new DepositContract();
        //deploy eigen. send eigen tokens to an address where they won't trigger failure for 'transfer to non ERC1155Receiver implementer,'
        eigen = new Eigen(address(this));

        deposit = new EigenLayrDeposit(consensusLayerDepositRoot);
        deposit = EigenLayrDeposit(address(new TransparentUpgradeableProxy(address(deposit), address(eigenLayrProxyAdmin), "")));
        //do stuff this eigen token here
        delegation = new EigenLayrDelegation();
        delegation = EigenLayrDelegation(address(new TransparentUpgradeableProxy(address(delegation), address(eigenLayrProxyAdmin), "")));
        slasher = new Slasher(investmentManager, address(this));
        serviceFactory = new ServiceFactory(investmentManager, delegation);
        investmentManager = new InvestmentManager(eigen, delegation, serviceFactory);
        investmentManager = InvestmentManager(address(new TransparentUpgradeableProxy(address(investmentManager), address(eigenLayrProxyAdmin), "")));
        //used in the one investment strategy
        weth = new ERC20PresetFixedSupply(
            "weth",
            "WETH",
            wethInitialSupply,
            address(this)
        );
        //do stuff with weth
        strat = new WethStashInvestmentStrategy();
        strat = WethStashInvestmentStrategy(address(new TransparentUpgradeableProxy(address(strat), address(eigenLayrProxyAdmin), "")));
        strat.initialize(address(investmentManager), weth);

        IInvestmentStrategy[] memory strats = new IInvestmentStrategy[](1);
        strats[0] = IInvestmentStrategy(address(strat));
        // WETH strategy added to InvestmentManager
        strategies[0] = IInvestmentStrategy(address(strat));

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
        assertTrue(address(dlRepository) != address(0), "dlRepository failed to deploy");
        assertTrue(address(deposit) != address(0), "deposit failed to deploy");
        assertTrue(dlRepository.ServiceManager() == dlsm, "ServiceManager set incorrectly");
        assertTrue(
            dlsm.repository() == dlRepository,
            "repository set incorrectly in dlsm"
        );
        assertTrue(
            dl.repository() == dlRepository,
            "repository set incorrectly in dl"
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

    //deposits 'amountToDeposit' of WETH from address 'sender' into 'strat'
    function _testWethDeposit(
        address sender,
        uint256 amountToDeposit)
        internal 
        returns (uint256 amountDeposited)
    {
        amountDeposited = _testWethDepositStrat(sender, amountToDeposit, strat);
    }


    //deposits 'amountToDeposit' of WETH from address 'sender' into the supplied 'stratToDepositTo'
    function _testWethDepositStrat(
        address sender,
        uint256 amountToDeposit,
        WethStashInvestmentStrategy stratToDepositTo)
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
                stratToDepositTo,
                weth,
                amountToDeposit
            );
            amountDeposited = amountToDeposit;
        }
        //in this case, since shares never grow, the shares should just match the deposited amount
        assertEq(
            investmentManager.investorStratShares(sender, stratToDepositTo),
            amountDeposited,
            "shares should match deposit"
        );
        cheats.stopPrank();
    }

   

    //Testing deposits in Eigen Layr Contracts - check msg.value
    function testDepositETHIntoConsensusLayer() 
        public 
        returns(uint256 amountDeposited)
    {
        amountDeposited = _testDepositETHIntoConsensusLayer(registrant, amountDeposited);
    }

    function _testDepositETHIntoConsensusLayer(
        address sender,
        uint256 amountToDeposit)
        internal
        returns(uint256 amountDeposited)
    {
        bytes32 depositDataRoot = depositContract.get_deposit_root();

        cheats.deal(sender, amountToDeposit);
        cheats.startPrank(sender);
        deposit.depositEthIntoConsensusLayer{value: amountToDeposit}("0x", "0x", depositDataRoot);
        amountDeposited = amountToDeposit;

        assertEq(investmentManager.consensusLayerEth(sender), amountDeposited);
        cheats.stopPrank();
    }

    function testDepositETHIntoLiquidStaking()
        public
        returns(uint256 amountDeposited)
    {
        amountDeposited = _testDepositETHIntoLiquidStaking(registrant, 10, strat);
    }


    //reverts for some reason?
    function _testDepositETHIntoLiquidStaking(
        address sender,
        uint256 amountToDeposit,
        WethStashInvestmentStrategy stratToDepositTo)
        internal
        returns(uint256 amountDeposited)
    {
        if (amountToDeposit > wethInitialSupply) {
            cheats.expectRevert(
                bytes("ERC20: transfer amount exceeds balance")
            );

            weth.transfer(sender, amountToDeposit);
            amountDeposited = 0;
        } else {
            weth.transfer(sender, amountToDeposit);
            emit log_named_uint("WETH BALANCE", weth.balanceOf(sender));
            cheats.startPrank(sender);
            deposit.depositETHIntoLiquidStaking{value: amountToDeposit}(weth, stratToDepositTo);
            
            amountDeposited = amountToDeposit;
        }
        
        assertEq(
            investmentManager.investorStratShares(sender, stratToDepositTo),
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
        dlsm.initDataStore(
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

    //verifies that it is possible to deposit eigen
    function testDepositEigen() public {
        _testDepositEigen(registrant);
    }

    //deposits a fixed amount of eigen from address 'sender'
    //checks that the deposit is credited correctly
    function _testDepositEigen(address sender) public {
        uint256 toDeposit = 1e16;
        eigen.safeTransferFrom(address(this), sender, 0, toDeposit, "0x");
        cheats.startPrank(sender);
        eigen.setApprovalForAll(address(investmentManager), true);

        investmentManager.depositEigen(toDeposit);

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
            //TODO: write this properly
            uint8(delegation.delegated(sender)) == 1,
            "_testSelfOperatorDelegate: delegation not credited?"
        );
    }

    function testSelfOperatorRegister()
        public
        returns (bytes memory)
    {
        // emptyStakes is used in place of stakes, since right now they are empty (two totals of 12 zero bytes each)
        bytes memory emptyStakes = abi.encodePacked(bytes24(0));
        return _testRegisterAdditionalSelfOperator(registrant, emptyStakes);
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
        dlRegVW.registerOperator(sender, data);

        uint48 dumpNumber = dlRegVW.stakeHashUpdates(dlRegVW.getStakesHashUpdateLength() - 1);
        uint96 weightOfOperatorEth = uint96(dlRegVW.weightOfOperatorEth(sender));
        uint96 weightOfOperatorEigen = uint96(dlRegVW.weightOfOperatorEigen(sender));
        bytes memory stakes = abi.encodePacked(
            stakesPrev.slice(0,stakesPrev.length - 24),
            sender,
            weightOfOperatorEth,
            weightOfOperatorEigen,
            weightOfOperatorEth + (stakesPrev.toUint96(stakesPrev.length - 24)),
            weightOfOperatorEigen + (stakesPrev.toUint96(stakesPrev.length - 12))
        );
        bytes32 hashOfStakes = keccak256(stakes);
        assertTrue(
            hashOfStakes == dlRegVW.stakeHashes(dumpNumber),
            "_testRegisterAdditionalSelfOperator: stakes stored incorrectly"
        );

        cheats.stopPrank();
        return (stakes);
    }

    //verifies that it is possible to confirm a data store
    //checks that the store is marked as committed
    function testConfirmDataStore() public {
        testConfirmDataStoreSelfOperators(1);
    }

    function testConfirmDataStoreTwoOperators() public {
        testConfirmDataStoreSelfOperators(2);
    }

    function testConfirmDataStoreTwelveOperators() public {
        testConfirmDataStoreSelfOperators(12);
    }

    function testConfirmDataStoreSelfOperators(uint8 signersInput) public {
        cheats.assume(signersInput > 0 && signersInput <= 12);

        uint32 numberOfSigners = uint32(signersInput);

        //loads hardcoded signer set
        _setSigners();

        //initial stakes is 24 zero bytes
        bytes memory stakes = abi.encodePacked(bytes24(0));

        //register all the operators
        for (uint256 i = 0; i < numberOfSigners; ++i) {
            // emit log_named_uint("i", i);
            stakes = _testRegisterAdditionalSelfOperator(signers[i], stakes);
        }

        bytes32 headerHash = _testInitDataStore();
        bytes32 signedHash = ECDSA.toEthSignedMessageHash(headerHash);
        uint48 currentDumpNumber = dlsm.dumpNumber();
        //start forming the data object
        bytes memory data = abi.encodePacked(
            currentDumpNumber,
            headerHash,
            numberOfSigners,
            uint256(dlRegVW.getStakesHashUpdateLength() - 1),
            stakes.length,
            stakes
        );

        //sign the headerHash with each signer, and append the signature to the data object
        for (uint256 j = 0; j < numberOfSigners; ++j) {
            (uint8 v, bytes32 r, bytes32 s) = cheats.sign(keys[j], signedHash);
            // emit log_named_address("recovered address", ecrecover(signedHash, v, r, s));  
            address recoveredAddress = ecrecover(signedHash, v, r, s);
            if (recoveredAddress != signers[j]) {
                emit log_named_address("bad signature from", recoveredAddress);
                emit log_named_address("expected signature from", signers[j]);
            } 
            bytes32 vs = SignatureCompaction.packVS(s,v);
            data = abi.encodePacked(
                data,
                r,
                vs,
                //signatory's index in stakes object
                uint32(j)
            );
        }

        // emit log_named_bytes("stakes", stakes);
        // emit log_named_bytes("data", data);
        cheats.prank(storer);

        uint256 gasbefore = gasleft();
        dlsm.confirmDataStore(data);
        emit log_named_uint("gas spent on confirm, testConfirmDataStoreSelfOperators()", gasbefore - gasleft());
        emit log_named_uint("number of operators", numberOfSigners);
         
        (, , ,bool committed) = dl.dataStores(headerHash);
        assertTrue(committed, "Data store not committed");
        cheats.stopPrank();
    }

    // registers a fixed address as a delegate, delegates to it from a second address, and checks that the delegate's voteWeights increase properly
    function testDelegation() public {
      
        uint96 registrantEthWeightBefore = uint96(dlRegVW.weightOfOperatorEth(registrant));
        uint96 registrantEigenWeightBefore = uint96(dlRegVW.weightOfOperatorEigen(registrant));
        DelegationTerms dt = _deployDelegationTerms(registrant);
        _testRegisterAsDelegate(registrant, dt);
        _testWethDeposit(acct_0, 1e18);
        _testDepositEigen(acct_0);
        _testDelegateToOperator(acct_0, registrant);
        _testDelegateToBySignature(acct_1, registrant, uint256(priv_key_1));
    
        uint96 registrantEthWeightAfter = uint96(dlRegVW.weightOfOperatorEth(registrant));
        uint96 registrantEigenWeightAfter = uint96(dlRegVW.weightOfOperatorEigen(registrant));
        assertTrue(registrantEthWeightAfter > registrantEthWeightBefore, "testDelegation: registrantEthWeight did not increase!");
        assertTrue(registrantEigenWeightAfter > registrantEigenWeightBefore, "testDelegation: registrantEigenWeight did not increase!");
        IInvestmentStrategy _strat = delegation.operatorStrats(registrant, 0);
        assertTrue(address(_strat) != address(0), "operatorStrats not updated correctly");
        assertTrue(delegation.operatorShares(registrant, _strat) > 0, "operatorShares not updated correctly");
        // emit log_named_uint("operatorShares", delegation.operatorShares(registrant, _strat));
    }

    function _deployDelegationTerms(address operator) internal returns (DelegationTerms) {
        address[] memory paymentTokens = new address[](1);
        paymentTokens[0] = address(weth);
        uint16 _MAX_OPERATOR_FEE_BIPS = 500;
        uint16 _operatorFeeBips = 500;
        DelegationTerms dt = 
            new DelegationTerms(
                operator,
                investmentManager,
                paymentTokens,
                serviceFactory,
                address(delegation),
                _MAX_OPERATOR_FEE_BIPS,
                _operatorFeeBips
            );
        assertTrue(address(dt) != address(0), "_deployDelegationTerms: DelegationTerms failed to deploy");
        return dt;
    }

    function _testRegisterAsDelegate(address sender, DelegationTerms dt) internal {
        cheats.startPrank(sender);
        delegation.registerAsDelegate(dt);
        assertTrue(delegation.delegationTerms(sender) == dt, "_testRegisterAsDelegate: delegationTerms not set appropriately");
        cheats.stopPrank();
    }

    function _testDelegateToOperator(address sender, address operator) internal {
        cheats.startPrank(sender);
        delegation.delegateTo(operator);
        assertTrue(delegation.delegation(sender) == operator, "_testDelegateToOperator: delegated address not set appropriately");
        //TODO: write this properly
        assertTrue(uint8(delegation.delegated(sender)) == 1, "_testDelegateToOperator: delegated status not set appropriately");
        // TODO: add more checks?
        cheats.stopPrank();
    }


    function _testDelegateToBySignature(address sender, address operator, uint256 priv_key) internal {
        cheats.startPrank(sender);
        bytes32 structHash = keccak256(
            abi.encode(
                delegation.DELEGATION_TYPEHASH(), sender, operator, 0, 0
                )
        );
        bytes32 digestHash = keccak256(
            abi.encodePacked(
            "\x19\x01", delegation.DOMAIN_SEPARATOR(), structHash)
            );

        (uint8 v, bytes32 r, bytes32 s) = cheats.sign((priv_key), digestHash);
        bytes32 vs;
        
        (r, vs) = SignatureCompaction.packSignature(r, s, v);
        delegation.delegateToBySignature(sender, operator, 0, 0, r, vs);
    }

    function testAddStrategies(uint16 numStratsToAdd) public {
        cheats.assume(numStratsToAdd > 0 && numStratsToAdd <= 20);
        for (uint16 i = 1; i < numStratsToAdd; ++i) {
            WethStashInvestmentStrategy strategy = new WethStashInvestmentStrategy();
            // deploying these as upgradeable proxies was causing a weird stack overflow error, so we're just using implementation contracts themselves for now
            // strategy = WethStashInvestmentStrategy(address(new TransparentUpgradeableProxy(address(strat), address(eigenLayrProxyAdmin), "")));
            strategy.initialize(address(investmentManager), weth);
            // add strategy to InvestmentManager
            IInvestmentStrategy[] memory stratsToAdd = new IInvestmentStrategy[](1);
            stratsToAdd[0] = IInvestmentStrategy(address(strategy));
            investmentManager.addInvestmentStrategies(stratsToAdd);
            // check that investmentManager storage is updated accordingly
            assertTrue(investmentManager.stratApproved(IInvestmentStrategy(address(strategy))), "strategy not approved");
            assertTrue(investmentManager.stratEverApproved(IInvestmentStrategy(address(strategy))), "strategy not approved");
            //store strategy in mapping
            strategies[i] = IInvestmentStrategy(address(strategy));
        }
    }

    function _testDepositStrategies(address sender, uint256 amountToDeposit, uint16 numStratsToAdd) internal {
        cheats.assume(numStratsToAdd > 0 && numStratsToAdd <= 20);
        testAddStrategies(numStratsToAdd);
        for (uint16 i = 0; i < numStratsToAdd; ++i) {
            _testWethDepositStrat(sender, amountToDeposit, WethStashInvestmentStrategy(address(strategies[i])));
            assertTrue(investmentManager.investorStrats(sender, i) == strategies[i], "investorStrats array updated incorrectly");
        }
        assertTrue(investmentManager.investorStratsLength(sender) == numStratsToAdd, "investorStratsLength incorrect");

    }

    function testDepositStrategies(uint16 numStratsToAdd) public {
        _testDepositStrategies(registrant, 1e18, numStratsToAdd);
    }

    // registers a fixed address as a delegate, delegates to it from a second address, and checks that the delegate's voteWeights increase properly
    function testDelegationMultipleStrategies(uint16 numStratsToAdd) public {
        cheats.assume(numStratsToAdd > 0 && numStratsToAdd <= 20);
        uint96 registrantEthWeightBefore = uint96(dlRegVW.weightOfOperatorEth(registrant));
        uint96 registrantEigenWeightBefore = uint96(dlRegVW.weightOfOperatorEigen(registrant));
        DelegationTerms dt = _deployDelegationTerms(registrant);
        _testRegisterAsDelegate(registrant, dt);
        _testDepositStrategies(acct_0, 1e18, numStratsToAdd);
        _testDepositEigen(acct_0);
        _testDelegateToOperator(acct_0, registrant);
        uint96 registrantEthWeightAfter = uint96(dlRegVW.weightOfOperatorEth(registrant));
        uint96 registrantEigenWeightAfter = uint96(dlRegVW.weightOfOperatorEigen(registrant));
        assertTrue(registrantEthWeightAfter > registrantEthWeightBefore, "testDelegation: registrantEthWeight did not increase!");
        assertTrue(registrantEigenWeightAfter > registrantEigenWeightBefore, "testDelegation: registrantEigenWeight did not increase!");
        IInvestmentStrategy _strat = delegation.operatorStrats(registrant, 0);
        assertTrue(address(_strat) != address(0), "operatorStrats not updated correctly");
        assertTrue(delegation.operatorShares(registrant, _strat) > 0, "operatorShares not updated correctly");

        for (uint16 i = 0; i < numStratsToAdd; ++i) {
            IInvestmentStrategy depositorStrat = investmentManager.investorStrats(acct_0, i);
            // emit log_named_uint("delegation.operatorShares(registrant, depositorStrat)", delegation.operatorShares(registrant, depositorStrat));
            // emit log_named_uint("investmentManager.investorStratShares(registrant, depositorStrat)", investmentManager.investorStratShares(acct_0, depositorStrat));
            assertTrue(
                delegation.operatorShares(registrant, depositorStrat)
                ==
                investmentManager.investorStratShares(acct_0, depositorStrat),
                "delegate shares not stored properly"
            );
        }
    }
}
