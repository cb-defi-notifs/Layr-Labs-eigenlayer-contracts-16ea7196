// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./mocks/DepositContract.sol";
import "./mocks/LiquidStakingToken.sol";
import "../contracts/governance/Timelock.sol";

import "../contracts/core/Eigen.sol";

import "../contracts/interfaces/IEigenLayrDelegation.sol";
import "../contracts/core/EigenLayrDelegation.sol";
import "../contracts/core/EigenLayrDeposit.sol";
import "../contracts/core/DelegationTerms.sol";

import "../contracts/investment/InvestmentManager.sol";
import "../contracts/investment/WethStashInvestmentStrategy.sol";
import "../contracts/investment/HollowInvestmentStrategy.sol";
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

import "../contracts/libraries/BLS.sol";
import "../contracts/libraries/BytesLib.sol";
import "../contracts/libraries/SignatureCompaction.sol";

import "./CheatCodes.sol";
import "./Signers.sol";

//TODO: encode data properly so that we initialize TransparentUpgradeableProxy contracts in their constructor rather than a separate call (if possible)
contract EigenLayrDeployer is
    DSTest,
    ERC165_Universal,
    ERC1155TokenReceiver,
    Signers
{
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
    DataLayrDisclosureChallengeFactory
        public dataLayrDisclosureChallengeFactory;

    WETH public liquidStakingMockToken;
    WethStashInvestmentStrategy public liquidStakingMockStrat;

    bytes[] registrationData;

    // strategy index => IInvestmentStrategy
    mapping(uint256 => IInvestmentStrategy) public strategies;
    mapping(IInvestmentStrategy => uint256) public initialOperatorShares;
    // number of strategies deployed
    uint256 public numberOfStrats;

    //strategy indexes for undelegation (see commitUndelegation function)
    uint256[] public strategyIndexes;

    uint256 wethInitialSupply = 10e50;
    uint256 undelegationFraudProofInterval = 7 days;
    uint256 consensusLayerEthToEth = 10;
    uint256 timelockDelay = 2 days;
    bytes32 consensusLayerDepositRoot =
        0x9c4bad94539254189bb933df374b1c2eb9096913a1f6a3326b84133d2b9b9bad;
    address storer = address(420);
    address registrant = address(0x4206904396bF2f8b173350ADdEc5007A52664293); //sk: e88d9d864d5d731226020c5d2f02b62a4ce2a4534a39c225d32d3db795f83319

    //from testing seed phrase
    bytes32 priv_key_0 =
        0x1234567812345678123456781234567812345678123456781234567812345678;
    address acct_0 = cheats.addr(uint256(priv_key_0));

    bytes32 priv_key_1 =
        0x1234567812345678123456781234567812345698123456781234567812348976;
    address acct_1 = cheats.addr(uint256(priv_key_1));

    //performs basic deployment before each test
    function setUp() virtual public  {
        eigenLayrProxyAdmin = new ProxyAdmin();

        //eth2 deposit contract
        depositContract = new DepositContract();
        //deploy eigen. send eigen tokens to an address where they won't trigger failure for 'transfer to non ERC1155Receiver implementer,'
        eigen = new Eigen(address(this));

        deposit = new EigenLayrDeposit(consensusLayerDepositRoot);
        deposit = EigenLayrDeposit(
            address(
                new TransparentUpgradeableProxy(
                    address(deposit),
                    address(eigenLayrProxyAdmin),
                    ""
                )
            )
        );
        //do stuff this eigen token here
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
        slasher = new Slasher(investmentManager, address(this));
        serviceFactory = new ServiceFactory(investmentManager, delegation);
        investmentManager = new InvestmentManager(
            eigen,
            delegation,
            serviceFactory
        );
        investmentManager = InvestmentManager(
            address(
                new TransparentUpgradeableProxy(
                    address(investmentManager),
                    address(eigenLayrProxyAdmin),
                    ""
                )
            )
        );
        //used in the one investment strategy
        weth = new ERC20PresetFixedSupply(
            "weth",
            "WETH",
            wethInitialSupply,
            address(this)
        );
        //do stuff with weth
        strat = new WethStashInvestmentStrategy();
        strat = WethStashInvestmentStrategy(
            address(
                new TransparentUpgradeableProxy(
                    address(strat),
                    address(eigenLayrProxyAdmin),
                    ""
                )
            )
        );
        strat.initialize(address(investmentManager), weth);

        IInvestmentStrategy[] memory strats = new IInvestmentStrategy[](3);

        HollowInvestmentStrategy temp = new HollowInvestmentStrategy();
        temp.initialize(address(investmentManager));
        strats[0] = temp;
        strategies[1] = temp;
        temp = new HollowInvestmentStrategy();
        temp.initialize(address(investmentManager));
        strats[1] = temp;
        strategies[2] = temp;
        strats[2] = IInvestmentStrategy(address(strat));
        // WETH strategy added to InvestmentManager
        strategies[0] = IInvestmentStrategy(address(strat));

        address governor = address(this);
        investmentManager.initialize(
            strats,
            slasher,
            governor,
            address(deposit)
        );

        delegation.initialize(
            investmentManager,
            serviceFactory,
            slasher,
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

        dlRepository = new Repository(delegation, investmentManager);

        // IInvestmentStrategy[] memory strats = new IInvestmentStrategy[](1);
        // strats[0] = IInvestmentStrategy(address(strat));
        dlRegVW = new DataLayrVoteWeigher(
            Repository(address(dlRepository)),
            delegation,
            investmentManager,
            consensusLayerEthToEth,
            strats
        );

        Repository(address(dlRepository)).initialize(
            dlRegVW,
            dlsm,
            dlRegVW,
            timelockDelay
        );

        dl.setRepository(dlRepository);
        dlsm.setRepository(dlRepository);
        dlsm.setDataLayr(dl);

        deposit.initialize(depositContract, investmentManager, dlsm);

        liquidStakingMockToken = new WETH();
        liquidStakingMockStrat = new WethStashInvestmentStrategy();
        liquidStakingMockStrat.initialize(
            address(investmentManager),
            IERC20(address(liquidStakingMockToken))
        );

        //loads hardcoded signer set
        _setSigners();
        registrationData.push(hex"0a94806675ea2f011a001d18e7a261ea7c8d1f902884e647e637e5e577fcd66400217cf55fa5e35ade042501f1486966ecd482b53f14d9dc3c001e2fa484c449962a85c5c465244cfc5163c9f14d8bdb56dbea1ff8685e99636e9076df87117a201c4a79e305e295d9bf9a61becbf95e76262fffc88888f2bcf83876c86431cf462864d48f11719fab32967a3b6d547124a6bcfcfb0891887a282b6688ba4158d7");
        registrationData.push(hex"2ffd6171073c0e545073a9bc7c452d2677974f29540ed71fd1933dfc02629a660021ebaab8a762a1beaecd9e378bcc6525ab53aeed4f9a5d21c27aea78f413ea461d4aa348699d79e54916f5c7b545bc95c556b91a923596928c52035658bbeb88181fb59de5e8a87ed94a7757e79f64c947b62b1bf7d08e2fe4c4fd88f68180fb03c0035a93e7dadda09303a1e4e7be8018dfcc67919d7f82a79fc4e3e3138f45");
        registrationData.push(hex"06cb60fa77995fef4c3f56ee5b74a6963c9b53e8dd91937fdef6574f9b5db56b0105e4c920e32a0469ba7e00f873e9cf2e0848aff1bb1fe80a4923aeadcde7c2592c5defc05811861e09e7cd10cf5042da406d11d8af66a3e3e3b4c5c31507be3413b340fa427dbacbe981d02c850a58ffa5af850b9d2e53bb5b99c6c235fa4c0208d3d99d5bec30411c822eb592302427507296c86c94660d9fc129c2bad333b3");
        registrationData.push(hex"174f94b12b5628c554319f4871093e6657c57247416611804006d6cbbc3f47d3010916b81be3ae37e2bc6eff35a081317de6e88eb5b245af3e3cc8e8cf1410b33d07bc410121cea80da157a2ad7082c8d849c48bf430f4c5dc92a86ce201b39b7c2c4478ce29f331128e1005d53924cdde59fcac805210b620ecac33db87765ed11a10157f4ae7a30b5fd4c122a6bd3ee6a04f1f717a76b325bd51e0a1e9aec3c4");
        registrationData.push(hex"209fe56fe29a93e108d735b086b7de6a932d1abd6d70d15689785e0538ce43910029469c20b0a16654a0215bbad542c5210550c85c021cc0842378eff0dac80fa2130c9d145baaad1a6251c221dd991fb90ed0dad3fd4203780bdb25a0cb8c346e2acca2648ab1886db2a65052a3075cc0993c5052d7c4b84e4eda218637db18710c3567986dea2ed30016a418725fb3d21e60fb072618851f14f5c38077346c16");
        registrationData.push(hex"1a826a2953682088a2f84b2295d729d22aef96a2b543cfb8341802764482d543002dfcabd0075583de7305a61e14b07c314b6184f454faf213a3e8504608a23d2402e1d6824dd1a30ea7398ec95b4877979b6a176269a1b5d213f4cce668c5655e02452456e3bcea2666a50b06e030a9bad2caa028313b2b8cbca35303624c99fc1e2e7300b8d2c79933ca478bc764ef09f4d9eea5d864550984d978280e3f30bc");
        registrationData.push(hex"20043c208cc8d16d1648eb160bc5a9a69d97def0778700bd93342265c8e1fe8b010c6a6cc438514f3579d4241c3404eb2c57fef6f84eeafc10669c6a42b9ef2e261eac24d04dfa7e1fffb07865288ffdebe24094acf1a15f2b57af3d11e1798c5a28ac16141b09b94d90cd23e7db07cc2c759d52d94b5746921d491b031ddb8c1123710005ed7788a843df024bd5b7253fcde14a944c02cddccb7e204759c3a402");
        registrationData.push(hex"266356b759998d7865cc43666979a4e55443a31d6f79a95db4c63aaa0feb53d60000f9f42f10116d3b616748406dafce11814d424a9e6b55c518dc2d4b8482815819997da97fc609e4a9a3b48b4a6aeaf74ed5c975ab34179565664e9af13ddec802cce476dc270b74cf01aa69fbc0853850c9897e6dd2ca365d7fb3668be30b8c0312c1aeb59e0e72a1258237bb40e9cdec653ce8480ae9f0a24083c91de290cd");
        registrationData.push(hex"05afc73ebe6ad85b90e238ba92a25533db875eb09c8ea0ea84c33fa27349d15e01148f603a5c8b70d271ca089645f1edba811f8ad1ea0e461364d0756172f194131cabf63a23857d1c982d35fa61aef6b33d6b9a817b36cb22595347afd1a283001f3021d6fd579bd350584abe31237e0e523d2f0102e9733830d9adbe4bf8d7c80cd61ebdf2df7d6d77fdc254fda89de607187bfc42cdbc77e6fb3cac3bec5a1f");
        registrationData.push(hex"1f7eb3a98e544d6d86bd517d83cde98494ff22ed4bc2adb13c32819920d267dd00216fe46ac550db4f5a9afd82bcdeac529076206fccdf4a56ea43a41131400d6a1d6236e1a788ccba2f0d7517111612573384f77f16e24870175ed4757a45c7f125b04215fa6035599709911783275196ee4bebdb41ab81af9e7e0198ab6650e70484bf5d5c79ed47a65f77f7ef8265bb35024d3dcfd12cd30fe62815a10ce979");
        registrationData.push(hex"1d77b2a20afed3a528a4dee6b3bffc1fd9d7a1385093161c4327394b02f5487201227e01159f9e9c2ad6186452037bc393344fed31b7bce64b88858663c92bc53f2910d6491e9cd6eafb4e49bef78477a6de2f16b2d2257ca91dc8f46672f1924312d6e03fe3ced2051b262bedd8bef32e8afebdce64ce03ac57da5d1eac4adfd20ab9cf5972ae412593ef4a61a7fb0d46d820a2ed0982cdc3ea997fee8644ba1b");
        registrationData.push(hex"2984f278d7240ec84524ec7b0d1ab198150c1ac0921fea5412a039a75d71f7d2012ca7448feb6c1a66f6a10df59426ddaddb504518a28ffc092f84fa0ac141aae006b14859c56f012d4b484121e15a8ed14b17a9f30f190a71f2fe8219a2734db72d8d9d516d61e02cbb653efc46953672161c79332261e42f0982b59229b9f4be2641e670866e49142f85fb104b07f14848d7c68c74024fc32f0b2ce7a88c1835");
        registrationData.push(hex"0b959fb5a7e444f81bc7f64146b7a01a029a323d4d2cea12f323a26b714b14d90123f84391d1838688da2c8e7aa1e5162b63ecfaf76690f53fca17c23fe66848e12ce535322df1c220239216b39bb1cd3f45d29185d3203b5314eec420b10583ad013ba8092d0e24ab77da734dfd1761dd7ea9af4c058431c51fb7b046b0a332b42a73d9818b2b53f22c8f3cc0c44a5bf497b76f045bccbd0b4f414146dfdf4d39");
        registrationData.push(hex"2833747188c0471f00de01fbc7195022b541d562ced648a86f149cf7aec3d543002ef9a05caa70028a4b99ed0cba3341fb4f6773570a27147a4f5619dca46e266611f7ea600a3511ba61ff4e171167f9c088c5869615d4b7d1a85b03dd4f68aef82c876b9dabe12d4a972b15bcd4d374efd667f4e2324dcd07e861416b726ad8c31df8bc4410b6a2b0255c5c8c19a3902d48c8bf82ee7cd5e5714ea00f8bf3c3d8");
        registrationData.push(hex"1e53397e7a398cd41a04a103394592d878fe3a93bf3fa750590ba89cae512fcf000f396f1a8d944b1fcbe2877b3e99a2da9f540641afadd0a0abc8023c935b1303265760a58d2fe92c8088312fae0a1f14a8716b179de670e1aa864a8e4de97e5b20407dbcf523ae4171eee01357f92eb407a30a4b30f372cd9f6266e6650d3b0a03c15c863f3a591d76bd6b9ab62a8300fc71a2325a7b400cf7319efeec849d01");
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
        assertTrue(
            address(dlRepository) != address(0),
            "dlRepository failed to deploy"
        );
        assertTrue(address(deposit) != address(0), "deposit failed to deploy");
        assertTrue(
            dlRepository.serviceManager() == dlsm,
            "ServiceManager set incorrectly"
        );
        assertTrue(
            dlsm.repository() == dlRepository,
            "repository set incorrectly in dlsm"
        );
        assertTrue(
            dl.repository() == dlRepository,
            "repository set incorrectly in dl"
        );
    }

    function testaaaaaaaaaaaaaaaaaaaaaaaaaaaa() public {
        (uint256 pk_x, uint256 pk_y) = BLS.verifyBLSSigOfPubKeyHash(registrationData[0]);
    }

    //verifies that depositing WETH works
    function testWethDeposit(uint256 amountToDeposit)
        public
        returns (uint256 amountDeposited)
    {
        return _testWethDeposit(registrant, amountToDeposit);
    }

    //deposits 'amountToDeposit' of WETH from address 'sender' into 'strat'
    function _testWethDeposit(address sender, uint256 amountToDeposit)
        internal
        returns (uint256 amountDeposited)
    {
        amountDeposited = _testWethDepositStrat(sender, amountToDeposit, strat);
    }

    //deposits 'amountToDeposit' of WETH from address 'sender' into the supplied 'stratToDepositTo'
    function _testWethDepositStrat(
        address sender,
        uint256 amountToDeposit,
        WethStashInvestmentStrategy stratToDepositTo
    ) internal returns (uint256 amountDeposited) {
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
        returns (uint256 amountDeposited)
    {
        amountDeposited = _testDepositETHIntoConsensusLayer(
            registrant,
            amountDeposited
        );
    }

    function _testDepositETHIntoConsensusLayer(
        address sender,
        uint256 amountToDeposit
    ) internal returns (uint256 amountDeposited) {
        bytes32 depositDataRoot = depositContract.get_deposit_root();

        cheats.deal(sender, amountToDeposit);
        cheats.startPrank(sender);
        deposit.depositEthIntoConsensusLayer{value: amountToDeposit}(
            "0x",
            "0x",
            depositDataRoot
        );
        amountDeposited = amountToDeposit;

        assertEq(
            investmentManager.getConsensusLayerEth(sender),
            amountDeposited
        );
        cheats.stopPrank();
    }

    function testDepositETHIntoLiquidStaking()
        public
        returns (uint256 amountDeposited)
    {
        return
            _testDepositETHIntoLiquidStaking(
                registrant,
                1e18,
                liquidStakingMockToken,
                liquidStakingMockStrat
            );
    }

    function _testDepositETHIntoLiquidStaking(
        address sender,
        uint256 amountToDeposit,
        IERC20 liquidStakingToken,
        IInvestmentStrategy stratToDepositTo
    ) internal returns (uint256 amountDeposited) {
        // sanity in the amount we are depositing
        cheats.assume(amountToDeposit < type(uint96).max);
        cheats.deal(sender, amountToDeposit);
        cheats.startPrank(sender);
        deposit.depositETHIntoLiquidStaking{value: amountToDeposit}(
            liquidStakingToken,
            stratToDepositTo
        );

        amountDeposited = amountToDeposit;

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
        //make sure their proofOfStakingEth has updated
        assertEq(investmentManager.getProofOfStakingEth(depositor), amount);
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
            delegation.isSelfOperator(sender),
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
        _testRegisterAdditionalSelfOperator(registrant, registrationData[0]);
    }

    function testTwoSelfOperatorsRegistersssssssssssssssssssssssssssssssssssss() public
    {
        address sender = acct_0;
        _testRegisterAdditionalSelfOperator(sender, registrationData[1]);
    }

    function _testRegisterAdditionalSelfOperator(
        address sender,
        bytes memory data
    ) internal {
        //register as both ETH and EIGEN operator
        uint8 registrantType = 3;
        _testWethDeposit(sender, 1e18);
        _testDepositEigen(sender);
        _testSelfOperatorDelegate(sender);
        string memory socket = "255.255.255.255";

        cheats.startPrank(sender);
        // function registerOperator(uint8 registrantType, bytes calldata data, string calldata socket)
        dlRegVW.registerOperator(registrantType, data, socket);

        cheats.stopPrank();
    }

    //verifies that it is possible to confirm a data store
    //checks that the store is marked as committed
    function testConfirmDataStoreeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee() public {
        _testConfirmDataStoreSelfOperators(15);
    }

    // function testConfirmDataStoreTwoOperators() public {
    //     testConfirmDataStoreSelfOperators(2);
    // }

    // function testConfirmDataStoreTwelveOperators() public {
    //     testConfirmDataStoreSelfOperators(12);
    // }

    function _testConfirmDataStoreSelfOperators(uint8 signersInput) public {
        cheats.assume(signersInput > 0 && signersInput <= 15);

        uint32 numberOfSigners = uint32(signersInput);

        //register all the operators
        for (uint256 i = 0; i < numberOfSigners; ++i) {
            // emit log_named_uint("i", i);
            _testRegisterAdditionalSelfOperator(signers[i], registrationData[i]);
        }
        bytes32 headerHash = _testInitDataStore();
        // uint48 dumpNumber,
        // bytes32 headerHash,
        // uint32 numberOfNonSigners,
        // bytes33[] compressedPubKeys of nonsigners
        // uint32 apkIndex
        // uint256[4] sigma

        uint32 currentDumpNumber = dlsm.dumpNumber();

        // //start forming the data object
        bytes memory data = abi.encodePacked(
            currentDumpNumber,
            headerHash,
            uint32(0),
            uint32(15),
            uint256(11509234998032783125480266028213992619847908725038453197451386571405359529652),
            uint256(4099696940551850412667065443628214990719002449715926250279745743126938401735),
            uint256(19060191254988907833052035421850065496347936631097225966803157637464336346786),
            uint256(16129402215257578064845163124174157135534373400489420174780024516864802406908)
        );

        // //sign the headerHash with each signer, and append the signature to the data object
        // for (uint256 j = 0; j < numberOfSigners; ++j) {
        //     (uint8 v, bytes32 r, bytes32 s) = cheats.sign(keys[j], signedHash);
        //     // emit log_named_address("recovered address", ecrecover(signedHash, v, r, s));
        //     address recoveredAddress = ecrecover(signedHash, v, r, s);
        //     if (recoveredAddress != signers[j]) {
        //         emit log_named_address("bad signature from", recoveredAddress);
        //         emit log_named_address("expected signature from", signers[j]);
        //     }
        //     bytes32 vs = SignatureCompaction.packVS(s,v);
        //     data = abi.encodePacked(
        //         data,
        //         r,
        //         vs,
        //         //signatory's index in stakes object
        //         uint32(j)
        //     );
        // }

        // // emit log_named_bytes("stakes", stakes);
        // emit log_named_bytes("data", data);
        // cheats.prank(storer);

        uint256 gasbefore = gasleft();
        dlsm.confirmDataStore(data);
        emit log_named_uint("gas spent on confirm, testConfirmDataStoreSelfOperators()", gasbefore - gasleft());
        emit log_named_uint("number of operators", numberOfSigners);

        (, , ,bool committed) = dl.dataStores(headerHash);
        // assertTrue(committed, "Data store not committed");
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
        // IInvestmentStrategy _strat = delegation.operatorStrats(registrant, 0);
        // assertTrue(address(_strat) != address(0), "operatorStrats not updated correctly");
        // assertTrue(delegation.operatorShares(registrant, _strat) > 0, "operatorShares not updated correctly");

    }

    function _testRegisterAsDelegate(address sender, DelegationTerms dt) internal {
        cheats.startPrank(sender);
        delegation.registerAsDelegate(dt);
        assertTrue(delegation.delegationTerms(sender) == dt, "_testRegisterAsDelegate: delegationTerms not set appropriately");
        cheats.stopPrank();
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


     function _testDelegateToOperator(address sender, address operator) internal {
         cheats.startPrank(sender);
         delegation.delegateTo(operator);
         assertTrue(delegation.delegation(sender) == operator, "_testDelegateToOperator: delegated address not set appropriately");
         //TODO: write this properly
         assertTrue(uint8(delegation.delegated(sender)) == 1, "_testDelegateToOperator: delegated status not set appropriately");
         // TODO: add more checks?
         cheats.stopPrank();
     }

    //     function _testDelegateToBySignature(address sender, address operator, uint256 priv_key) internal {
    //         cheats.startPrank(sender);
    //         bytes32 structHash = keccak256(
    //             abi.encode(
    //                 delegation.DELEGATION_TYPEHASH(), sender, operator, 0, 0
    //                 )
    //         );
    //         bytes32 digestHash = keccak256(
    //             abi.encodePacked(
    //             "\x19\x01", delegation.DOMAIN_SEPARATOR(), structHash)
    //             );

    //         (uint8 v, bytes32 r, bytes32 s) = cheats.sign((priv_key), digestHash);
    //         bytes32 vs;

    //         (r, vs) = SignatureCompaction.packSignature(r, s, v);
    //         delegation.delegateToBySignature(sender, operator, 0, 0, r, vs);
    //         assertTrue(delegation.delegation(sender) == operator, "no delegation relation between sender and operator");
    //         cheats.stopPrank();

    function testAddStrategies(uint16 numStratsToAdd) public {
        cheats.assume(numStratsToAdd > 0 && numStratsToAdd <= 20);
        for (uint16 i = 1; i < numStratsToAdd; ++i) {
            WethStashInvestmentStrategy strategy = new WethStashInvestmentStrategy();
            // deploying these as upgradeable proxies was causing a weird stack overflow error, so we're just using implementation contracts themselves for now
            // strategy = WethStashInvestmentStrategy(address(new TransparentUpgradeableProxy(address(strat), address(eigenLayrProxyAdmin), "")));
            strategy.initialize(address(investmentManager), weth);
            // add strategy to InvestmentManager
            // IInvestmentStrategy[] memory stratsToAdd = new IInvestmentStrategy[](1);
            // stratsToAdd[0] = IInvestmentStrategy(address(strategy));
            //store strategy in mapping
            strategies[i] = IInvestmentStrategy(address(strategy));
        }
    }

    function _testDepositStrategies(address sender, uint256 amountToDeposit, uint16 numStratsToAdd) internal {
        cheats.assume(numStratsToAdd > 0 && numStratsToAdd <= 20);
        testAddStrategies(numStratsToAdd);
        for (uint16 i = 0; i < numStratsToAdd; ++i) {
            _testWethDepositStrat(sender, amountToDeposit, WethStashInvestmentStrategy(address(strategies[i])));
            // removed testing of deprecated functionality
            // assertTrue(investmentManager.investorStrats(sender, i) == strategies[i], "investorStrats array updated incorrectly");
        }
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
        // IInvestmentStrategy _strat = delegation.operatorStrats(registrant, 0);
        // assertTrue(address(_strat) != address(0), "operatorStrats not updated correctly");
        // assertTrue(delegation.operatorShares(registrant, _strat) > 0, "operatorShares not updated correctly");

        // TODO: reintroduce similar check
        // for (uint16 i = 0; i < numStratsToAdd; ++i) {
        //     IInvestmentStrategy depositorStrat = investmentManager.investorStrats(acct_0, i);
        //     // emit log_named_uint("delegation.operatorShares(registrant, depositorStrat)", delegation.operatorShares(registrant, depositorStrat));
        //     // emit log_named_uint("investmentManager.investorStratShares(registrant, depositorStrat)", investmentManager.investorStratShares(acct_0, depositorStrat));
        //     assertTrue(
        //         delegation.operatorShares(registrant, depositorStrat)
        //         ==
        //         investmentManager.investorStratShares(acct_0, depositorStrat),
        //         "delegate shares not stored properly"
        //     );

        // }
    }


//TODO: add tests for contestDelegationCommit() 
    function testUndelegation() public {

        //delegate
        DelegationTerms dt = _deployDelegationTerms(registrant);
        _testRegisterAsDelegate(registrant, dt);
        _testWethDeposit(acct_0, 1e18);
        _testDepositEigen(acct_0);
        _testDelegateToOperator(acct_0, registrant);

// TODO: update this to work at all again
        //delegator-specific information
        (IInvestmentStrategy[] memory delegatorStrategies, uint256[] memory delegatorShares) = investmentManager.getDeposits(msg.sender);

        //mapping(IInvestmentStrategy => uint256) memory initialOperatorShares;
        for (uint256 k = 0; k < delegatorStrategies.length; k++ ){
            initialOperatorShares[delegatorStrategies[k]] = delegation.getOperatorShares(registrant, delegatorStrategies[k]);
        }

        // //TODO: maybe wanna test with multple strats and exclude some? strategyIndexes are strategies the delegator wants to undelegate from
        // for (uint256 j = 0; j< delegation.getOperatorStrats(registrant).length; j++){
        //     strategyIndexes.push(j);
        // }

        _testUndelegation(acct_0);

        for (uint256 k = 0; k < delegatorStrategies.length; k++ ){
            uint256 operatorSharesBefore = initialOperatorShares[delegatorStrategies[k]];
            uint256 operatorSharesAfter = delegation.getOperatorShares(registrant, delegatorStrategies[k]);
            assertTrue(delegatorShares[k] == operatorSharesAfter - operatorSharesBefore);
        }
    }

    function _testUndelegation(address sender) internal{
        cheats.startPrank(sender);
        cheats.warp(block.timestamp+1000000);
        delegation.commitUndelegation();
        delegation.finalizeUndelegation();
        cheats.stopPrank();
    }
}