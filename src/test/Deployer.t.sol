// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./mocks/DepositContract.sol";
import "./mocks/LiquidStakingToken.sol";

import "../contracts/core/Eigen.sol";

import "../contracts/interfaces/IEigenLayrDelegation.sol";
import "../contracts/core/EigenLayrDelegation.sol";
import "../contracts/core/EigenLayrDeposit.sol";
import "../contracts/core/DelegationTerms.sol";

import "../contracts/investment/InvestmentManager.sol";
import "../contracts/investment/InvestmentStrategyBase.sol";
import "../contracts/investment/HollowInvestmentStrategy.sol";
import "../contracts/investment/Slasher.sol";

import "../contracts/middleware/ServiceFactory.sol";
import "../contracts/middleware/Repository.sol";
import "../contracts/middleware/DataLayr/DataLayr.sol";
import "../contracts/middleware/DataLayr/DataLayrServiceManager.sol";
import "../contracts/middleware/DataLayr/DataLayrRegistry.sol";
import "../contracts/middleware/DataLayr/DataLayrPaymentChallenge.sol";
import "../contracts/middleware/DataLayr/DataLayrEphemeralKeyRegistry.sol";
import "../contracts/middleware/DataLayr/DataLayrChallengeUtils.sol";
import "../contracts/middleware/DataLayr/DataLayrLowDegreeChallenge.sol";
import "../contracts/middleware/DataLayr/DataLayrDisclosureChallenge.sol";

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "forge-std/Test.sol";

import "../contracts/utils/ERC165_Universal.sol";
import "../contracts/utils/ERC1155TokenReceiver.sol";

import "../contracts/libraries/BLS.sol";
import "../contracts/libraries/BytesLib.sol";
import "../contracts/libraries/SignatureCompaction.sol";

import "./utils/Signers.sol";

//TODO: encode data properly so that we initialize TransparentUpgradeableProxy contracts in their constructor rather than a separate call (if possible)
contract EigenLayrDeployer is
    DSTest,
    ERC165_Universal,
    ERC1155TokenReceiver,
    Signers
{
    using BytesLib for bytes;

    Vm cheats = Vm(HEVM_ADDRESS);
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
    DataLayrLowDegreeChallenge public dlldc;
    DataLayr public dl;

    IERC20 public weth;
    InvestmentStrategyBase public strat;
    IRepository public dlRepository;

    ProxyAdmin public eigenLayrProxyAdmin;

    DataLayrPaymentChallenge public dataLayrPaymentChallenge;
    DataLayrDisclosureChallenge public dataLayrDisclosureChallenge;

    WETH public liquidStakingMockToken;
    InvestmentStrategyBase public liquidStakingMockStrat;

    uint256 nonce = 69;

    bytes[] registrationData;

    // strategy index => IInvestmentStrategy
    mapping(uint256 => IInvestmentStrategy) public strategies;
    // number of strategies deployed
    uint256 public numberOfStrats;

    //strategy indexes for undelegation (see commitUndelegation function)
    uint256[] public strategyIndexes;

    uint256 wethInitialSupply = 10e50;
    uint256 undelegationFraudProofInterval = 7 days;
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

    bytes32 public ephemeralKey =
        0x3290567812345678123456781234577812345698123456781234567812344389;

    uint256 public constant eigenTokenId = 0;
    uint256 public constant eigenTotalSupply = 1000e18;

    //performs basic deployment before each test
    function setUp() public {
        // deploy proxy admin for ability to upgrade proxy contracts
        eigenLayrProxyAdmin = new ProxyAdmin();

        //eth2 deposit contract
        depositContract = new DepositContract();
        //deploy eigen. send eigen tokens to an address where they won't trigger failure for 'transfer to non ERC1155Receiver implementer'
        // (this is why this contract inherits from 'ERC1155TokenReceiver')
        // eigen = new Eigen(address(this));

        // deploy deposit contract implementation, then create upgradeable proxy that points to implementation
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

        // deploy delegation contract implementation, then create upgradeable proxy that points to implementation
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

        // deploy slasher and service factory contracts
        slasher = new Slasher(investmentManager, address(this));
        serviceFactory = new ServiceFactory(investmentManager, delegation);

        // deploy InvestmentManager contract implementation, then create upgradeable proxy that points to implementation
        investmentManager = new InvestmentManager(delegation);
        investmentManager = InvestmentManager(
            address(
                new TransparentUpgradeableProxy(
                    address(investmentManager),
                    address(eigenLayrProxyAdmin),
                    ""
                )
            )
        );

        //simple ERC20 (*NOT WETH-like!), used in a test investment strategy
        weth = new ERC20PresetFixedSupply(
            "weth",
            "WETH",
            wethInitialSupply,
            address(this)
        );

        // deploy InvestmentStrategyBase contract implementation, then create upgradeable proxy that points to implementation
        strat = new InvestmentStrategyBase();
        strat = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(strat),
                    address(eigenLayrProxyAdmin),
                    ""
                )
            )
        );
        // initialize InvestmentStrategyBase proxy
        strat.initialize(address(investmentManager), weth);

        eigenToken = new ERC20PresetFixedSupply(
            "eigen",
            "EIGEN",
            wethInitialSupply,
            address(this)
        );
        // deploy InvestmentStrategyBase contract implementation, then create upgradeable proxy that points to implementation
        eigenStrat = new InvestmentStrategyBase();
        eigenStrat = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(eigenStrat),
                    address(eigenLayrProxyAdmin),
                    ""
                )
            )
        );
        // initialize InvestmentStrategyBase proxy
        eigenStrat.initialize(address(investmentManager), eigenToken);

        // create 'HollowInvestmentStrategy' contracts for 'ConsenusLayerEth' and 'ProofOfStakingEth'
        IInvestmentStrategy[] memory strats = new IInvestmentStrategy[](2);
        HollowInvestmentStrategy temp = new HollowInvestmentStrategy();
        temp.initialize(address(investmentManager));
        strats[0] = temp;
        strategies[0] = temp;
        temp = new HollowInvestmentStrategy();
        temp.initialize(address(investmentManager));
        strats[1] = temp;
        strategies[1] = temp;
        // add WETH strategy to mapping
        strategies[2] = IInvestmentStrategy(address(strat));

        // actually initialize the investmentManager (proxy) contraxt
        address governor = address(this);
        investmentManager.initialize(
            strats,
            slasher,
            governor,
            address(deposit)
        );

        // initialize the delegation (proxy) contract
        delegation.initialize(
            investmentManager,
            undelegationFraudProofInterval
        );

        // deploy all the DataLayr contracts
        _deployDataLayrContracts();

        // initialize the deposit (proxy) contract
        // must wait until after the DL contracts are deployed since it relies on the DLSM for updates to ProofOfStaking
        deposit.initialize(depositContract, investmentManager, dlsm);

        // set up a strategy for a mock liquid staking token
        liquidStakingMockToken = new WETH();
        liquidStakingMockStrat = new InvestmentStrategyBase();
        liquidStakingMockStrat.initialize(
            address(investmentManager),
            IERC20(address(liquidStakingMockToken))
        );

        //loads hardcoded signer set
        _setSigners();
        registrationData.push(
            hex"075dcd2e66658b1f4f61aa809f001bb79324b91089af99b9a78e27284e8c73130d884d46e54bf17137028ddc3fd38d5b89686b7c433099b28149f9c8f771c8431f5bda9b7d94f525e0f9b667127df9fa884e9917453db7fe3119820b994b5e5d2428c354c0019c338afd3994e186d7d443ec1d8abab2e2d1e19bac019ee295f20fd9f812e64d2be18573054ece7aef8a3fae1618068b08cfdc9722d4254a5c1c1c3241bc604d574aef221cfa3e7abd0334554fdae446fa2258a36c1bb725110d"
        );
        registrationData.push(
            hex"2669082021fd1033646a940aabe3f459e7b7a808d959c392af45c91b3fe064960bce92bfb1a54bc1af73b41a1edb13bd9e5006471c5d4708f77ea530f1045b7a0914646c43c0b404345c7864daa76091996c36227ac5b2ad5a7468ab49ebaf7b13357d53c87adfee0aa3b2c7dbca5d00660c4c5ed1acbeebb4c9202101dab4f01d21849e7ec98d09ba242b6f5ca31407f9819acd40f4aa036e7bbacbdd3af2d42f0a64cc4b8ee3af7a898ca674219743ca599d7b0506a371ba79161524fad80d"
        );
        registrationData.push(
            hex"142b758de8ad4c74e8167d71b3667cf75e982f006480ecafdde2a403748e7d1b2dd77f6eac473a31fddba53321584cd0aa296f14d14f098093937a5b93dd61c90cc3e0a7657c894d178a7ff41ae51b5ccc4c697684c599015b003aceeb2fec641863a130465043a63a1acf5494ee76895779044613264c5f65a106834b6615901ac1b422373760d0769efe667a1af135e7447a97b906dc3b4b3d56546eb8ecc31a25249cfff25b5a742b3690ba9c88cdeba85b6b20d0c77353fe7a548efdfc8a"
        );
        registrationData.push(
            hex"2af2ac3833ce14949c9ef3fbccf620e3a13c9df686687634f9546a76ec5899f7219bfb0cf2f2817525cd89082302218c3cf83b3beae6c4fbe25ae4a790e948d307d64b5418c89567b5956590d6232c4ed95afd9d06d5a13b1f9c0c306a9260fe04783304a0c560710cb4f1bdc8096e7a67e39be589513dc644845b2e66fc19dd084bba4c75ba9dafb4e83e6c8de24ae1dff9ec06812c211321df381d09aa44691e4c3d98475d044e547281470e5dc33098943c018299e08ab3c89b70d452926a"
        );
        registrationData.push(
            hex"2c63a558d2384cf3f387db39c48c3b72595ef13adbc3ca7689bc90bae7e4ab060620e82d1bb6c52977529ece1fe1d31b0521492a06c661e06363b3be8306acd10746c80e9dacb5731c65232cf5fb5a2450e4f2e44d44fbc9d6cbf19dd30db776226488c51bfacbf7704d12065eb3ad1b9a707a4f61d41effdcb2ced3e01c4269147423e6e542b715c56e5e0b005348a71e3375e5301710c58017b78919a3c10707a9573924f2b6f5044a231d2a70a61b8b064fc97ec29f072d862f5d399a1476"
        );
        registrationData.push(
            hex"0076c0c034a6916e712bb41ed97530c4475c78c89f916137511d03ee94b670691a904a8de426166c9a7e6e3e36260973db56b218336dc89c68e2710026abe9e61612d3f5da47c52b552d66322623d688f5046baa625e4f66556cafed25c61980017458bcef061aafd36e998f0f5958439f175df8ffd3a286bc4986eafdb6d4701c07ff8c6632b0d251c106f434171de8ea44271f0e68a2b5e070376ae35aecfe1f4bde7af27b8dee86137ccf31685ec72185a52154a719087a363326a81713db"
        );
        registrationData.push(
            hex"1fb489ea26c1b85899bad2104702946ef256a7e59f26080bfddce2a64e94e3991947cd387f975963abc04838968f3eb128263b73c57c6820107395eca138fd98100bcb4ba69885f5020187520c35df6ff5b991b01bab7b83ad63c23af7e03b0c1efe7165964b7e66443b25b76fe6717739760afae192948aed7ae74f81564255190add561a44c0bd1234f01bad469e63dfd915eb9da9e49ee2f71f72cf554f021ef6b31132d974049e139f4389ec34a2b7404b67e55db7da768907d10801069a"
        );
        registrationData.push(
            hex"0e7fc7b5bca43de3fab4acc5a7a014bb9bb5aff171cb26ae31bffe2bc529db0f1269f9809e4069bddf06aaf88187192e241fb817a6c8bbb5aff3836a0520e6b61aca04d4cc4f83d755ac2e9e083197afee1ea77d42e9429fa4b3fb64276f78001e7951e39e5de9c4c89e41fc0fbcf8f59438e85a60d1ac40293ab862f1b4c3bd1182464e8fd0d33351275c3e02d0adbb593d6fc34c7b251becca6ef19e70d91025d14a460697676e73f4c259be24d71b6d59dc5f5ec3026ad9ce50f0c314af65"
        );
        registrationData.push(
            hex"18b1f796356a80ea2cc1c0e23a3e7331a97a417473cf83a5f6942ecf9a84cc351a187ceef1a2436db814c6d5a83b16b6dd48f69b23d07f7e3544cf9f3a4edd8a031b8f1c6711edff8267eb49c6a9ecd2de39eaea18621db1f601186b6c8b56ee1a7bb20411a152aaac50010240dad6f82a7dc818fe6565db4132350d69eaeec60b0306663891836f6d11cde6af281687d4703b3c45abb1b3c18519491b1986f30d38c69d223be9fb4733b490f4da70c9694bc73496b341e5fa428f1ed59ba41d"
        );
        registrationData.push(
            hex"15ba1ac04f35335cfd1c9c1fcaac012871e3543bb7876b38be193e3f07592aab0323619b00d87f3c03d4bab25c91b8bc4b7aa96818930f2b4684ae8f6e92464b30298b441eaadcfb3b86e0b3f0e41250060dbb89e34c2d67acef7ed9a2590db42108f4f14af5ff87b2b9b7d766c4be119b790f34c9b3b1a62d16f6a95935d2e01ea7023966c26530c81055e0a50c5062918357effe2eb0b9e9c5662d62ed92ce01c43aa265da0850a4b60dd33b66cc9a9ad3037c7dd2a6a0a9611a698f227d3c"
        );
        registrationData.push(
            hex"0822ccd871333690ea42c6e7fa1b594c785d8296fc8bacc8a10ddda8f3378ebb0d68db879257ec3f74d4fc1cffd17a9f1b6db08b7c421753dbce0751d6d7d23a07873fdb87a38f72a537da1cc20b48d1186594430718e15ec5e195ab3c65f8102f6a351c01b3cfc217c9ab936382a53b9a350851ecbaf43e6a0f086bf8ec395401693e8f639b1d98d81719c2f9fcdb45ba37bba1ecc4343c8daaf3e44d5f2e8e20acc7c63d987f4a5fe894c3f205b9e2425433fe6b5278d53351f8b4bd6aa705"
        );
        registrationData.push(
            hex"1a6962a7170cf4ea2ad4bd0bf9a95c4e6bf96e9302e345b9d12bfbf6fb86dc911733c8198257dc9003ba0163d217b48fdb14e6ce91691242064ae21d821980481ad1e21ac4adc2eebad1e279e490b307aafafcf43a3e63decb19f7dac7d5a26c1fa208243839cf96ee3218652239dc06119770cebe08776c1bd92af9626f04d01a0f55e82e7c08ea1d868630d37e874ba7ad3038264a13b7a5ca0939973502cb191aacc894a8abb566cd982f607deb0c18f3abf846fc3eb6843cbbaa9738d588"
        );
        registrationData.push(
            hex"13185695a1abc17847ce6a90edc65eb04c0ebd218156f122ef689674e82ebb331ad5be86a500c6b0b490cbe70610356448aa2b06442f364b138fe7cd0df5efa9294cbc1ccb8c6afdbc05938f368521351328222ac99388e7a26c4f9d51ad1024042a5a5286bbcc22f94e95555be8a193731c2c265b64aa25fde8a047202a6d95051ae01267d28a2fd5e0b1b150709f5ea825727bd6e458223ada31fa2cce53181428260faa6fc03cdde9a77b82eaece16808ff3bc767ab159adb2047081f233c"
        );
        registrationData.push(
            hex"1db8d40c46e9992c0e020568b3f1c02fa4aef44c5db1610325093280218f2ab014c3ab56f0d82ad9ff275fae94e51a17c613302e5aa2f2de7001ae181727f8d4053c3d457ad36273361e3b35d02cea6c93879a55f0d086a77e58dc0d5805c6b428fc018be860797143a2b0296ed35113addbf3c0e8aaf6ea93c0acb3db78bae105d176cce68e50136fb116ad9eb04ddf0d810bf07c2e2bf39c56dea317744fa20eb7fc03d877c15b1e6a4c021c604ce4b629a475678c3888a997a398551813b0"
        );
        registrationData.push(
            hex"16bb52aa5a1e51cf22ac1926d02e95fdeb411ad48b567337d4c4d5138e84bd5516a6e1e18fb4cd148bd6b7abd46a5d6c54444c11ba5a208b6a8230e86cc8f80828427fd024e29e9a31945cd91433fde23fc9656a44424794a9dfdcafa9275baa06d5b28737bc0a5c21279b3c5309e35287cd72deb204abf6d6c91a0e0b38d0a414b5c501b3a03cd83ef2c1d31e0d46f6087f498b508aab54710fe6bcb7922a5a103bc846a08ed3768a9542b7293bf0d254134427070a9f2f88d47e566a21c741"
        );
    }

    // deploy all the DataLayr contracts. Relies on many EL contracts having already been deployed.
    function _deployDataLayrContracts() internal {
        DataLayrChallengeUtils challengeUtils = new DataLayrChallengeUtils();

        dlRepository = new Repository(delegation, investmentManager);

        uint256 feePerBytePerTime = 1;
        dlsm = new DataLayrServiceManager(
            delegation,
            weth,
            weth,
            dlRepository,
            feePerBytePerTime
        );

        dataLayrPaymentChallenge = new DataLayrPaymentChallenge(weth, dlsm);

        dl = new DataLayr(dlRepository);
        ephemeralKeyRegistry = new DataLayrEphemeralKeyRegistry(dlRepository);

        VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[]
            memory ethStratsAndMultipliers = new VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[](
                3
            );
        for (uint256 i = 0; i < ethStratsAndMultipliers.length; ++i) {
            ethStratsAndMultipliers[i].strategy = strategies[i];
            // TODO: change this if needed
            ethStratsAndMultipliers[i].multiplier = 1e18;
        }
        VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[]
            memory eigenStratsAndMultipliers = new VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[](
                1
            );
        eigenStratsAndMultipliers[0].strategy = eigenStrat;
        eigenStratsAndMultipliers[0].multiplier = 1e18;
        dlReg = new DataLayrRegistry(
            Repository(address(dlRepository)),
            delegation,
            investmentManager,
            ephemeralKeyRegistry,
            ethStratsAndMultipliers,
            eigenStratsAndMultipliers
        );

        Repository(address(dlRepository)).initialize(
            dlReg,
            dlsm,
            dlReg,
            address(this)
        );
        dlldc = new DataLayrLowDegreeChallenge(dlsm, dl, dlReg, challengeUtils);
        dataLayrDisclosureChallenge = new DataLayrDisclosureChallenge(
            dlsm,
            dl,
            dlReg,
            challengeUtils
        );

        dlsm.setDataLayr(dl);
    }

    // function testE2() public {
    //     uint256 gas0 = gasleft();
    //     E2.addJac(
    //         [
    //             16940785324452348635992944982086905647516261030288644621829277832435093717162,
    //             8401401490756564420272172490354616701629587303716804186731922457199553655742,
    //             2200354257610182565441132732833438202174557018186746499397198993370265236514,
    //             17095333892345298111161738825425230498463317863159444866557946136283431204362,
    //             14785826602540123512392148344509005496249192475307252199759965538807164193833,
    //             9189660566391726585332029637137298967388607370887228656340655906244808497020
    //         ],
    //         [
    //             8608946071402414754779647538809012881798658144764473110808718496782042055227,
    //             19459316801049918887468319268321135760886708051969582642264761971195775635187,
    //             14283736377967057699345761116067961584816287250338548158996741478515831505730,
    //             19965855455731552503348993691856470574147482301480743704692714658398376561253,
    //             8870333478013170162127933423632957954153017927683413088478188690883867400508,
    //             20970188582830179325192502629380520565320228575180745883239595974499081486845
    //         ]
    //     );
    //     uint256 gas1 = gasleft();
    //     for (uint i = 0; i < 10; i++) {
    //         E2.addJac(
    //             [
    //                 16940785324452348635992944982086905647516261030288644621829277832435093717162,
    //                 8401401490756564420272172490354616701629587303716804186731922457199553655742,
    //                 2200354257610182565441132732833438202174557018186746499397198993370265236514,
    //                 17095333892345298111161738825425230498463317863159444866557946136283431204362,
    //                 14785826602540123512392148344509005496249192475307252199759965538807164193833,
    //                 9189660566391726585332029637137298967388607370887228656340655906244808497020
    //             ],
    //             [
    //                 8608946071402414754779647538809012881798658144764473110808718496782042055227,
    //                 19459316801049918887468319268321135760886708051969582642264761971195775635187,
    //                 14283736377967057699345761116067961584816287250338548158996741478515831505730,
    //                 19965855455731552503348993691856470574147482301480743704692714658398376561253,
    //                 8870333478013170162127933423632957954153017927683413088478188690883867400508,
    //                 20970188582830179325192502629380520565320228575180745883239595974499081486845
    //             ]
    //         );
    //     }
    //     uint256 gas11 = gasleft();
    //     for (uint i = 0; i < 10; i++) {
    //         E2.addJac(
    //             [13506727255773795144315680029704080214342843760127900558694278035844711794885,860777676355831110273799363891754093645878892944028645123888749647573809879,15267756830832320657395337524493875300654959775089810802936792127399318210629,10639898247497145090326046495696235139127036347688130755236390521164948859094,1,0],
    //             [5383953684893666017772726539111703322102615374017331155756544245098562797288,316269460602238916553457473369605945672938555548735193235768375330608440731,7318401266095658276660502776426314357535095760928025610265551016835940218097,11801648757969528274474441051262602082523509772031359996597572164316927345785,8647270789825366092544269303730475512613608392881797943184546360153410212675,21279796494994290180652092991392470278254072695376261510472781042329897718188]
    //         );
    //     }
    //     uint256 gas21 = gasleft();

    //     emit log_named_uint("1 addition", gas0 - gas1);
    //     emit log_named_uint("10 addition", gas1 - gas11);
    //     emit log_named_uint("10 addition more", gas11 - gas21);
    // }

    // TODO: @Gautham fix this to work again?
    // function testBLS_Basic() public {
    //     BLS.verifyBLSSigOfPubKeyHash(
    //         registrationData[0]
    //     );
    // }

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
        InvestmentStrategyBase stratToDepositTo
    ) internal returns (uint256 amountDeposited) {
        //trying to deposit more than the wethInitialSupply will fail, so in this case we expect a revert and return '0' if it happens
        // s

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

    //initiates a data store
    //checks that the dataStoreId, initTime, storePeriodLength, and committed status are all correct
    function _testInitDataStore() internal returns (bytes32) {
        bytes memory header = abi.encodePacked(hex"0102030405060708091011121314151617181920");
        uint32 totalBytes = 1e6;
        uint8 duration = 2;

        // weth is set as the paymentToken of dlsm, so we must approve dlsm to transfer weth
        weth.transfer(storer, 1e11);
        cheats.startPrank(storer);
        weth.approve(address(dlsm), type(uint256).max);
        dlsm.depositFutureFees(storer, 1e11);

        uint32 blockNumber = 1;
        // change block number to 100 to avoid underflow in DataLayr (it calculates block.number - BLOCK_STALE_MEASURE)
        // and 'BLOCK_STALE_MEASURE' is currently 100
        cheats.roll(100);
        
        dlsm.initDataStore(header, duration, totalBytes, blockNumber);
        uint32 dataStoreId = dlsm.dataStoreId() - 1;
        bytes32 headerHash = keccak256(header);

        cheats.stopPrank();
        (
            uint32 dataStoreDataStoreId,
            uint32 dataStoreInitTime,
            uint32 dataStorePeriodLength,
            uint32 dataStoreBlockNumber
        ) = dl.dataStores(headerHash);
        emit log_named_uint("dataStoreDataStoreId", dataStoreDataStoreId);
        emit log_named_uint("dataStoreId", dataStoreId);

        assertTrue(
            dataStoreDataStoreId == dataStoreId,
            "_testInitDataStore: wrong dataStoreId"
        );
        assertTrue(
            dataStoreInitTime == uint32(block.timestamp),
            "_testInitDataStore: wrong initTime"
        );
        assertTrue(
            dataStorePeriodLength == duration * dlsm.DURATION_SCALE(),
            "_testInitDataStore: wrong storePeriodLength"
        );
        assertTrue(
            dataStoreBlockNumber == blockNumber,
            "_testInitDataStore: wrong blockNumber"
        );
        bytes32 sighash = dlsm.getDataStoreIdSignatureHash(dataStoreId);
        assertTrue(sighash == bytes32(0), "Data store not committed");
        return headerHash;
    }

    // deposits a fixed amount of eigen from address 'sender'
    // checks that the deposit is credited correctly
    function _testDepositEigen(address sender, uint256 toDeposit) public {
        eigenToken.transfer(sender, toDeposit);
        cheats.startPrank(sender);
        eigenToken.approve(address(investmentManager), type(uint256).max);
        investmentManager.depositIntoStrategy(
            sender,
            eigenStrat,
            eigenToken,
            toDeposit
        );
        // TODO: add this check back in
        // assertEq(
        //     investmentManager.eigenDeposited(sender),
        //     toDeposit,
        //     "_testDepositEigen: deposit not properly credited"
        // );
        cheats.stopPrank();
    }

    function _testSelfOperatorDelegate(address sender) internal {
        cheats.prank(sender);
        delegation.delegateToSelf();
        assertTrue(
            delegation.isSelfOperator(sender),
            "_testSelfOperatorDelegate: self delegation not properly recorded"
        );
        assertTrue(
            //TODO: write this properly to use the enum type defined in delegation
            uint8(delegation.delegated(sender)) == 1,
            "_testSelfOperatorDelegate: delegation not credited?"
        );
    }

    function _testRegisterAdditionalSelfOperator(
        address sender,
        bytes memory data
    ) internal {
        //register as both ETH and EIGEN operator
        uint8 registrantType = 3;
        uint256 wethToDeposit = 1e18;
        uint256 eigenToDeposit = 1e16;
        _testWethDeposit(sender, wethToDeposit);
        _testDepositEigen(sender, eigenToDeposit);
        _testSelfOperatorDelegate(sender);
        string memory socket = "255.255.255.255";

        cheats.startPrank(sender);
        // function registerOperator(uint8 registrantType, bytes calldata data, string calldata socket)

        dlReg.registerOperator(registrantType, ephemeralKey, data, socket);

        cheats.stopPrank();

        // verify that registration was stored correctly
        if ((registrantType & 1) == 1 && wethToDeposit > dlReg.dlnEthStake()) {
            assertTrue(
                dlReg.ethStakedByOperator(sender) == wethToDeposit,
                "ethStaked not increased!"
            );
        } else {
            assertTrue(
                dlReg.ethStakedByOperator(sender) == 0,
                "ethStaked incorrectly > 0"
            );
        }
        if (
            (registrantType & 2) == 2 && eigenToDeposit > dlReg.dlnEigenStake()
        ) {
            assertTrue(
                dlReg.eigenStakedByOperator(sender) == eigenToDeposit,
                "eigenStaked not increased!"
            );
        } else {
            assertTrue(
                dlReg.eigenStakedByOperator(sender) == 0,
                "eigenStaked incorrectly > 0"
            );
        }
    }

    // TODO: fix this to work with a variable number again, if possible
    function _testConfirmDataStoreSelfOperators(uint8 signersInput) internal {
        cheats.assume(signersInput > 0 && signersInput <= 15);

        uint32 numberOfSigners = uint32(signersInput);

        //register all the operators
        for (uint256 i = 0; i < numberOfSigners; ++i) {
            // emit log_named_uint("i", i);
            _testRegisterAdditionalSelfOperator(
                signers[i],
                registrationData[i]
            );
        }
        bytes32 headerHash = _testInitDataStore();
        uint32 numberOfNonSigners = 0;
        (uint256 apk_0, uint256 apk_1, uint256 apk_2, uint256 apk_3) = (
            uint256(
                20820493588973199354272631301248587752629863429201347184003644368113679196121
            ),
            uint256(
                18507428821816114421698399069438744284866101909563082454551586195885282320634
            ),
            uint256(
                1263326262781780932600377484793962587101562728383804037421955407439695092960
            ),
            uint256(
                3512517006108887301063578607317108977425754510174956792003926207778790018672
            )
        );
        (uint256 sigma_0, uint256 sigma_1) = (
            uint256(
                7155561537864411538991615376457474334371827900888029310878886991084477170996
            ),
            uint256(
                10352977531892356631551102769773992282745949082157652335724669165983475588346
            )
        );

        /** 
     @param data This calldata is of the format:
            <
             bytes32 headerHash,
             uint48 index of the totalStake corresponding to the dataStoreId in the 'totalStakeHistory' array of the DataLayrRegistry
             uint32 numberOfNonSigners,
             uint256[numberOfSigners][4] pubkeys of nonsigners,
             uint32 apkIndex,
             uint256[4] apk,
             uint256[2] sigma
            >
     */
        bytes memory data = abi.encodePacked(
            headerHash,
            uint48(dlReg.getLengthOfTotalStakeHistory() - 1),
            numberOfNonSigners,
            // no pubkeys here since zero nonSigners for now
            uint32(dlReg.getApkUpdatesLength() - 1),
            apk_0,
            apk_1,
            apk_2,
            apk_3,
            sigma_0,
            sigma_1
        );

        uint256 gasbefore = gasleft();
        dlsm.confirmDataStore(data);
        emit log_named_uint(
            "gas spent on confirm, testConfirmDataStoreSelfOperators()",
            gasbefore - gasleft()
        );
        emit log_named_uint("number of operators", numberOfSigners);

        bytes32 sighash = dlsm.getDataStoreIdSignatureHash(
            dlsm.dataStoreId() - 1
        );
        assertTrue(sighash != bytes32(0), "Data store not committed");
        cheats.stopPrank();
    }

    // simply tries to register 'sender' as a delegate, setting their 'DelegationTerms' contract in EigenLayrDelegation to 'dt'
    // verifies that the storage of EigenLayrDelegation contract is updated appropriately
    function _testRegisterAsDelegate(address sender, DelegationTerms dt)
        internal
    {
        cheats.startPrank(sender);
        delegation.registerAsDelegate(dt);
        assertTrue(
            delegation.delegationTerms(sender) == dt,
            "_testRegisterAsDelegate: delegationTerms not set appropriately"
        );
        cheats.stopPrank();
    }

    // deploys a DelegationTerms contract on behalf of 'operator', with several hard-coded values
    // does a simple check that deployment was successful
    // currently hard-codes 'weth' as the only payment token
    function _deployDelegationTerms(address operator)
        internal
        returns (DelegationTerms)
    {
        address[] memory paymentTokens = new address[](1);
        paymentTokens[0] = address(weth);
        uint16 _MAX_OPERATOR_FEE_BIPS = 500;
        uint16 _operatorFeeBips = 500;
        DelegationTerms dt = new DelegationTerms(
            operator,
            investmentManager,
            paymentTokens,
            address(delegation),
            dlRepository,
            _MAX_OPERATOR_FEE_BIPS,
            _operatorFeeBips
        );
        assertTrue(
            address(dt) != address(0),
            "_deployDelegationTerms: DelegationTerms failed to deploy"
        );
        return dt;
    }

    // tries to delegate from 'sender' to 'operator'
    // verifies that:
    //                  delegator has at least some shares
    //                  delegatedShares update correctly for 'operator'
    //                  delegated status is updated correctly for 'sender'
    function _testDelegateToOperator(address sender, address operator)
        internal
    {
        //delegator-specific information
        (
            IInvestmentStrategy[] memory delegateStrategies,
            uint256[] memory delegateShares
        ) = investmentManager.getDeposits(sender);

        uint256 numStrats = delegateShares.length;
        assertTrue(
            numStrats > 0,
            "_testDelegateToOperator: delegating from address with no investments"
        );
        uint256[] memory initialOperatorShares = new uint256[](numStrats);
        for (uint256 i = 0; i < numStrats; ++i) {
            initialOperatorShares[i] = delegation.getOperatorShares(
                operator,
                delegateStrategies[i]
            );
        }

        cheats.startPrank(sender);
        delegation.delegateTo(operator);
        cheats.stopPrank();

        assertTrue(
            delegation.delegation(sender) == operator,
            "_testDelegateToOperator: delegated address not set appropriately"
        );
        //TODO: write this properly to use the enum type defined in delegation
        assertTrue(
            uint8(delegation.delegated(sender)) == 1,
            "_testDelegateToOperator: delegated status not set appropriately"
        );

        for (uint256 i = 0; i < numStrats; ++i) {
            uint256 operatorSharesBefore = initialOperatorShares[i];
            uint256 operatorSharesAfter = delegation.getOperatorShares(
                operator,
                delegateStrategies[i]
            );
            assertTrue(
                operatorSharesAfter ==
                    (operatorSharesBefore + delegateShares[i]),
                "_testDelegateToOperator: delegatedShares not increased correctly"
            );
        }
    }

    // deploys a InvestmentStrategyBase contract and initializes it to treat 'weth' token as its underlying token
    function _testAddStrategy() internal returns (IInvestmentStrategy) {
        InvestmentStrategyBase strategy = new InvestmentStrategyBase();
        // deploying these as upgradeable proxies was causing a weird stack overflow error, so we're just using implementation contracts themselves for now
        // strategy = InvestmentStrategyBase(address(new TransparentUpgradeableProxy(address(strat), address(eigenLayrProxyAdmin), "")));
        strategy.initialize(address(investmentManager), weth);
        return strategy;
    }

    // deploys 'numStratsToAdd' strategies using '_testAddStrategy' and then deposits 'amountToDeposit' to each of them from 'sender'
    function _testDepositStrategies(
        address sender,
        uint256 amountToDeposit,
        uint16 numStratsToAdd
    ) internal {
        cheats.assume(numStratsToAdd > 0 && numStratsToAdd <= 20);
        IInvestmentStrategy[]
            memory stratsToDepositTo = new IInvestmentStrategy[](
                numStratsToAdd
            );
        for (uint16 i = 0; i < numStratsToAdd; ++i) {
            stratsToDepositTo[i] = _testAddStrategy();
            _testWethDepositStrat(
                sender,
                amountToDeposit,
                InvestmentStrategyBase(address(stratsToDepositTo[i]))
            );
        }
        for (uint16 i = 0; i < numStratsToAdd; ++i) {
            assertTrue(
                investmentManager.investorStrats(sender, i) ==
                    stratsToDepositTo[i],
                "investorStrats array updated incorrectly"
            );

            // TODO: perhaps remove this is we can. seems brittle if we don't track the number of strategies somewhere
            //store strategy in mapping of strategies
            strategies[i] = IInvestmentStrategy(address(stratsToDepositTo[i]));
        }
        // add strategies to dlRegistry
        for (uint16 i = 0; i < numStratsToAdd; ++i) {
            VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[]
                memory ethStratsAndMultipliers = new VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[](
                    1
                );
            ethStratsAndMultipliers[0].strategy = stratsToDepositTo[i];
            // TODO: change this if needed
            ethStratsAndMultipliers[0].multiplier = 1e18;
            dlReg.addStrategiesConsideredAndMultipliers(
                0,
                ethStratsAndMultipliers
            );
        }
    }

    function _testUndelegation(address sender) internal {
        cheats.startPrank(sender);
        cheats.warp(block.timestamp + 365 days);
        delegation.commitUndelegation();
        delegation.finalizeUndelegation();
        cheats.stopPrank();
    }

    // function testCheckSignatures() public {

    // }

    function testDeploymentSuccessful() public {
        assertTrue(
            address(depositContract) != address(0),
            "depositContract failed to deploy"
        );
        // assertTrue(address(eigen) != address(0), "eigen failed to deploy");
        assertTrue(
            address(eigenToken) != address(0),
            "eigenToken failed to deploy"
        );
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
        assertTrue(address(dlReg) != address(0), "dlReg failed to deploy");
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
}
