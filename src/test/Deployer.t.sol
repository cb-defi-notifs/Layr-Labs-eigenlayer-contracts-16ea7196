// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./mocks/LiquidStakingToken.sol";

import "../contracts/core/Eigen.sol";

import "../contracts/interfaces/IEigenLayrDelegation.sol";
import "../contracts/core/EigenLayrDelegation.sol";

import "../contracts/investment/InvestmentManager.sol";
import "../contracts/investment/InvestmentStrategyBase.sol";
import "../contracts/investment/HollowInvestmentStrategy.sol";
import "../contracts/investment/Slasher.sol";

import "../contracts/middleware/Repository.sol";
import "../contracts/middleware/DataLayr/DataLayrServiceManager.sol";
import "../contracts/middleware/BLSRegistryWithBomb.sol";
import "../contracts/middleware/DataLayr/DataLayrPaymentManager.sol";
import "../contracts/middleware/EphemeralKeyRegistry.sol";
import "../contracts/middleware/DataLayr/DataLayrChallengeUtils.sol";
import "../contracts/middleware/DataLayr/DataLayrLowDegreeChallenge.sol";

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "forge-std/Test.sol";

import "../contracts/libraries/BLS.sol";
import "../contracts/libraries/BytesLib.sol";
import "../contracts/libraries/DataStoreHash.sol";

import "./utils/Signers.sol";
import "./utils/SignatureUtils.sol";

//TODO: encode data properly so that we initialize TransparentUpgradeableProxy contracts in their constructor rather than a separate call (if possible)
contract EigenLayrDeployer is
    DSTest,
    Signers,
    SignatureUtils
{
    using BytesLib for bytes;

    uint256 public constant DURATION_SCALE = 1 hours;
    Vm cheats = Vm(HEVM_ADDRESS);
    // Eigen public eigen;
    IERC20 public eigenToken;
    InvestmentStrategyBase public eigenStrat;
    EigenLayrDelegation public delegation;
    InvestmentManager public investmentManager;
    EphemeralKeyRegistry public ephemeralKeyRegistry;
    Slasher public slasher;
    BLSRegistryWithBomb public dlReg;
    DataLayrServiceManager public dlsm;
    DataLayrLowDegreeChallenge public dlldc;

    IERC20 public weth;
    InvestmentStrategyBase public strat;
    IRepository public dlRepository;

    ProxyAdmin public eigenLayrProxyAdmin;

    DataLayrPaymentManager public dataLayrPaymentManager;

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

    uint8 durationToInit = 2;

    modifier cannotReinit(){
        cheats.expectRevert(
            bytes("Initializable: contract is already initialized")
        );
        _;
    }

    modifier fuzzedAddress(address addr){
        cheats.assume(addr != address(0));
        cheats.assume(addr != address(eigenLayrProxyAdmin));
        cheats.assume(addr != address(investmentManager));
        _;
    }

    //performs basic deployment before each test
    function setUp() public {
        // deploy proxy admin for ability to upgrade proxy contracts
        eigenLayrProxyAdmin = new ProxyAdmin();

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
        strat = new InvestmentStrategyBase(investmentManager);
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
        strat.initialize(weth);

        eigenToken = new ERC20PresetFixedSupply(
            "eigen",
            "EIGEN",
            wethInitialSupply,
            address(this)
        );
        // deploy InvestmentStrategyBase contract implementation, then create upgradeable proxy that points to implementation
        eigenStrat = new InvestmentStrategyBase(investmentManager);
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
        eigenStrat.initialize(eigenToken);

        // create 'HollowInvestmentStrategy' contracts for 'ConsenusLayerEth' and 'ProofOfStakingEth'
        IInvestmentStrategy[] memory strats = new IInvestmentStrategy[](2);
        HollowInvestmentStrategy temp = new HollowInvestmentStrategy(investmentManager);
        strats[0] = temp;
        strategies[0] = temp;
        temp = new HollowInvestmentStrategy(investmentManager);
        strats[1] = temp;
        strategies[1] = temp;
        // add WETH strategy to mapping
        strategies[2] = IInvestmentStrategy(address(strat));

        // actually initialize the investmentManager (proxy) contraxt
        address governor = address(this);
        // deploy slasher and service factory contracts
        slasher = new Slasher();
        slasher.initialize(investmentManager, delegation, governor);

        investmentManager.initialize(
            slasher,
            governor
        );

        // initialize the delegation (proxy) contract
        delegation.initialize(
            investmentManager,
            undelegationFraudProofInterval
        );

        // deploy all the DataLayr contracts
        _deployDataLayrContracts();

        // set up a strategy for a mock liquid staking token
        liquidStakingMockToken = new WETH();
        liquidStakingMockStrat = new InvestmentStrategyBase(investmentManager);
        liquidStakingMockStrat.initialize(
            IERC20(address(liquidStakingMockToken))
        );

        //loads hardcoded signer set
        _setSigners();

        //loads signatures
        setSignatures();

        registrationData.push(
            hex"075dcd2e66658b1f4f61aa809f001bb79324b91089af99b9a78e27284e8c73130d884d46e54bf17137028ddc3fd38d5b89686b7c433099b28149f9c8f771c8431f5bda9b7d94f525e0f9b667127df9fa884e9917453db7fe3119820b994b5e5d2428c354c0019c338afd3994e186d7d443ec1d8abab2e2d1e19bac019ee295f202a45cfe62ffb797ab25355a7f54788277f7fd9fda544ac6a7e38623d75fdd001074a61258b73d4773971a8073f04a6dd072409bea915d4ece0583c65f09fbfe"
        );
        registrationData.push(
            hex"2669082021fd1033646a940aabe3f459e7b7a808d959c392af45c91b3fe064960bce92bfb1a54bc1af73b41a1edb13bd9e5006471c5d4708f77ea530f1045b7a0914646c43c0b404345c7864daa76091996c36227ac5b2ad5a7468ab49ebaf7b13357d53c87adfee0aa3b2c7dbca5d00660c4c5ed1acbeebb4c9202101dab4f00953b9e7b44ec5991070966ed70c1cd37b03b06797059b6828b0a2abc1d5210c134a2cc96c98c4ed34e2c7399695d25c0c2dfce27e0885ad13b979eb1c465b99"
        );
        registrationData.push(
            hex"142b758de8ad4c74e8167d71b3667cf75e982f006480ecafdde2a403748e7d1b2dd77f6eac473a31fddba53321584cd0aa296f14d14f098093937a5b93dd61c90cc3e0a7657c894d178a7ff41ae51b5ccc4c697684c599015b003aceeb2fec641863a130465043a63a1acf5494ee76895779044613264c5f65a106834b6615902def894e6c296e5b789398128a3b8f05054314ee82739e8e51cea9e4432a000d028d664abd661c75fe7ed0506c347f3b94d782d82e2259c7ecb39c9796922b04"
        );
        registrationData.push(
            hex"2af2ac3833ce14949c9ef3fbccf620e3a13c9df686687634f9546a76ec5899f7219bfb0cf2f2817525cd89082302218c3cf83b3beae6c4fbe25ae4a790e948d307d64b5418c89567b5956590d6232c4ed95afd9d06d5a13b1f9c0c306a9260fe04783304a0c560710cb4f1bdc8096e7a67e39be589513dc644845b2e66fc19dd24fddaf89dd8e1f6ed4d5d8750fed28b4159442ea7edd367c9335bb07a3a00ea00bbc408f2a7336e2ac8694db6df7603708293aac6ee702cdfc0eefb32c37b27"
        );
        registrationData.push(
            hex"2c63a558d2384cf3f387db39c48c3b72595ef13adbc3ca7689bc90bae7e4ab060620e82d1bb6c52977529ece1fe1d31b0521492a06c661e06363b3be8306acd10746c80e9dacb5731c65232cf5fb5a2450e4f2e44d44fbc9d6cbf19dd30db776226488c51bfacbf7704d12065eb3ad1b9a707a4f61d41effdcb2ced3e01c42691f7631be59f69c691c082e7d192e4c4bbedab7c296ff6fc879e6f5511f3fc9a316f8e0f3a57a58ee42165206ec70f94ee1e80a41907f3ec36fb8cdeaaa08ca52"
        );
        registrationData.push(
            hex"0076c0c034a6916e712bb41ed97530c4475c78c89f916137511d03ee94b670691a904a8de426166c9a7e6e3e36260973db56b218336dc89c68e2710026abe9e61612d3f5da47c52b552d66322623d688f5046baa625e4f66556cafed25c61980017458bcef061aafd36e998f0f5958439f175df8ffd3a286bc4986eafdb6d47015e186650610a8d2d336913f53adff244280748c91ffc37d21179f2051deef662ce36aca626ad16812b5a8ffe3bb8c258154b7e962a90e72bd4732f21f808645"
        );
        registrationData.push(
            hex"1fb489ea26c1b85899bad2104702946ef256a7e59f26080bfddce2a64e94e3991947cd387f975963abc04838968f3eb128263b73c57c6820107395eca138fd98100bcb4ba69885f5020187520c35df6ff5b991b01bab7b83ad63c23af7e03b0c1efe7165964b7e66443b25b76fe6717739760afae192948aed7ae74f81564255264d1fac1a8f1c5d6f2d8e7e38ebdfc59a512c7281b5abfb727aa883a688f4381a970b882e097f1c1c754c9fd8ebc503a30488ffe821ac98bf79062f9b1d81c5"
        );
        registrationData.push(
            hex"0e7fc7b5bca43de3fab4acc5a7a014bb9bb5aff171cb26ae31bffe2bc529db0f1269f9809e4069bddf06aaf88187192e241fb817a6c8bbb5aff3836a0520e6b61aca04d4cc4f83d755ac2e9e083197afee1ea77d42e9429fa4b3fb64276f78001e7951e39e5de9c4c89e41fc0fbcf8f59438e85a60d1ac40293ab862f1b4c3bd0e225ae617a66cfc67ae42283156ff19878b9857cce60a2ae322075579cc8ed207d30ecd2feac39c5e2a7cacf6fe38c78a41b1b97313060b41a41b499477148c"
        );
        registrationData.push(
            hex"18b1f796356a80ea2cc1c0e23a3e7331a97a417473cf83a5f6942ecf9a84cc351a187ceef1a2436db814c6d5a83b16b6dd48f69b23d07f7e3544cf9f3a4edd8a031b8f1c6711edff8267eb49c6a9ecd2de39eaea18621db1f601186b6c8b56ee1a7bb20411a152aaac50010240dad6f82a7dc818fe6565db4132350d69eaeec62a47a927850ea2e09f6d0757d3f3201000eb58c24a9fa0160076433be84960ef031aeb05ae95495541e544f3a8345331f016ed542d05b64ca5076112faeb9b1a"
        );
        registrationData.push(
            hex"15ba1ac04f35335cfd1c9c1fcaac012871e3543bb7876b38be193e3f07592aab0323619b00d87f3c03d4bab25c91b8bc4b7aa96818930f2b4684ae8f6e92464b30298b441eaadcfb3b86e0b3f0e41250060dbb89e34c2d67acef7ed9a2590db42108f4f14af5ff87b2b9b7d766c4be119b790f34c9b3b1a62d16f6a95935d2e00463223946956732c65085bd6b2f3651944757099d6f643c0370fac983c27f1e0dc2b54a54fde7495e81d43c6346549cf824fb45ecd18f77d4537e8fba7e7e0c"
        );
        registrationData.push(
            hex"0822ccd871333690ea42c6e7fa1b594c785d8296fc8bacc8a10ddda8f3378ebb0d68db879257ec3f74d4fc1cffd17a9f1b6db08b7c421753dbce0751d6d7d23a07873fdb87a38f72a537da1cc20b48d1186594430718e15ec5e195ab3c65f8102f6a351c01b3cfc217c9ab936382a53b9a350851ecbaf43e6a0f086bf8ec395409fe90efaeae3703fbddaf8f331451d3dd3d138fce006af813b579d8c67313d71353b0fd3e02d50c77889d7095d09eb4874a7425604f20c3d7b619bf5efe3274"
        );
        registrationData.push(
            hex"1a6962a7170cf4ea2ad4bd0bf9a95c4e6bf96e9302e345b9d12bfbf6fb86dc911733c8198257dc9003ba0163d217b48fdb14e6ce91691242064ae21d821980481ad1e21ac4adc2eebad1e279e490b307aafafcf43a3e63decb19f7dac7d5a26c1fa208243839cf96ee3218652239dc06119770cebe08776c1bd92af9626f04d025cc5bff6c03978aab365592207f4e24fe1cce9eece22e86c84535ce3b0851732fb29f8709e77f2c38ee09f4eb3143fa17eb2381785485fa7990ee0b161367e7"
        );
        registrationData.push(
            hex"13185695a1abc17847ce6a90edc65eb04c0ebd218156f122ef689674e82ebb331ad5be86a500c6b0b490cbe70610356448aa2b06442f364b138fe7cd0df5efa9294cbc1ccb8c6afdbc05938f368521351328222ac99388e7a26c4f9d51ad1024042a5a5286bbcc22f94e95555be8a193731c2c265b64aa25fde8a047202a6d9501b635713a31a9322e81ad50f9331775856e610bfdb5546aadeb681143dc015023b5d07f7004ad42a5a2c74fd1c87991326b7575a75e73a347a7c59741d21db5"
        );
        registrationData.push(
            hex"1db8d40c46e9992c0e020568b3f1c02fa4aef44c5db1610325093280218f2ab014c3ab56f0d82ad9ff275fae94e51a17c613302e5aa2f2de7001ae181727f8d4053c3d457ad36273361e3b35d02cea6c93879a55f0d086a77e58dc0d5805c6b428fc018be860797143a2b0296ed35113addbf3c0e8aaf6ea93c0acb3db78bae1216edaa7fff2998dfd2adee5620745512c2faca1f547b996892eef199fe8bfd515696133c1920636012e494103e3c592283583296d73924bbacba7d299ca0e7d"
        );
        registrationData.push(
            hex"16bb52aa5a1e51cf22ac1926d02e95fdeb411ad48b567337d4c4d5138e84bd5516a6e1e18fb4cd148bd6b7abd46a5d6c54444c11ba5a208b6a8230e86cc8f80828427fd024e29e9a31945cd91433fde23fc9656a44424794a9dfdcafa9275baa06d5b28737bc0a5c21279b3c5309e35287cd72deb204abf6d6c91a0e0b38d0a41ae35db861ea707fc72c6b7756a6139e8cccf15392e59297c21af365de013b4312caa1e05d5aac7c5513fff386248f1955298f11e0e165ed9a20c9beefe2f8a0"
        );
    }

    // deploy all the DataLayr contracts. Relies on many EL contracts having already been deployed.
    function _deployDataLayrContracts() internal {
        DataLayrChallengeUtils challengeUtils = new DataLayrChallengeUtils();

        dlRepository = new Repository(delegation, investmentManager);

        uint256 feePerBytePerTime = 1;
        dlsm = new DataLayrServiceManager(
            investmentManager,
            delegation,
            dlRepository,
            weth,
            feePerBytePerTime
        );


        ephemeralKeyRegistry = new EphemeralKeyRegistry(dlRepository);

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
        uint8 _NUMBER_OF_QUORUMS = 2;
        dlReg = new BLSRegistryWithBomb(
            Repository(address(dlRepository)),
            delegation,
            investmentManager,
            ephemeralKeyRegistry,
            _NUMBER_OF_QUORUMS,
            ethStratsAndMultipliers,
            eigenStratsAndMultipliers
        );

        Repository(address(dlRepository)).initialize(
            dlReg,
            dlsm,
            dlReg,
            address(this)
        );
        uint256 _paymentFraudProofCollateral = 1e16;
        dataLayrPaymentManager = new DataLayrPaymentManager(
            weth,
            _paymentFraudProofCollateral,
            dlRepository,
            dlsm
        );
        dlldc = new DataLayrLowDegreeChallenge(dlsm, dlReg, challengeUtils);


        dlsm.setLowDegreeChallenge(dlldc);
        dlsm.setPaymentManager(dataLayrPaymentManager);
        dlsm.setEphemeralKeyRegistry(ephemeralKeyRegistry);
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


    //deposits 'amountToDeposit' of WETH from address 'sender' into 'strat'
    function _testWethDeposit(address sender, uint256 amountToDeposit)
        internal
        returns (uint256 amountDeposited)
    {
        // deposits will revert when amountToDeposit is 0
        cheats.assume(amountToDeposit > 0);
        amountDeposited = _testWethDepositStrat(sender, amountToDeposit, strat);
    }

    //deposits 'amountToDeposit' of WETH from address 'sender' into the supplied 'stratToDepositTo'
    function _testWethDepositStrat(
        address sender,
        uint256 amountToDeposit,
        InvestmentStrategyBase stratToDepositTo
    ) internal returns (uint256 amountDeposited) {
        uint256 operatorSharesBefore = investmentManager.investorStratShares(sender, stratToDepositTo);

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

            //check if depositor has never used this strat, that it is added correctly to investorStrats array.
            if(operatorSharesBefore == 0){
                // check that strategy is appropriately added to dynamic array of all of sender's strategies
                assertTrue(
                    investmentManager.investorStrats(sender, investmentManager.investorStratsLength(sender) - 1) ==
                        stratToDepositTo,
                    "investorStrats array updated incorrectly"
                );
            }
        }

        
        //in this case, since shares never grow, the shares should just match the deposited amount
        assertEq(
            investmentManager.investorStratShares(sender, stratToDepositTo) - operatorSharesBefore,
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
        uint256 wethBalanceBefore = weth.balanceOf(sender);
        _testWethDeposit(sender, amountToDeposit);
        uint256 amountDeposited = investmentManager.investorStratShares(sender, strat);
        cheats.prank(sender);

        //if amountDeposited is 0, then trying to withdraw will revert. expect a revert and *short-circuit* if it happens
        //TODO: figure out if making this 'expectRevert' work correctly is actually possible
        if (amountDeposited == 0) {
            // cheats.expectRevert(bytes("Index out of bounds."));
            // investmentManager.withdrawFromStrategy(0, strat, weth, amountToWithdraw);
            return;
        //trying to withdraw more than the amountDeposited will fail, so we expect a revert and *short-circuit* if it happens
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
            amountToWithdraw,
            wethBalanceAfter - wethBalanceBefore,
            "weth is missing somewhere"
        );
        cheats.stopPrank();
    }

    //initiates a data store
    //checks that the dataStoreId, initTime, storePeriodLength, and committed status are all correct
   function _testInitDataStore(uint256 timeStampForInit, address confirmer)
        internal
        returns (IDataLayrServiceManager.DataStoreSearchData memory searchData)
    {
        bytes memory header = abi.encodePacked(
            hex"0102030405060708091011121314151617181920"
        );
        uint32 totalBytes = 1e6;

        // weth is set as the paymentToken of dlsm, so we must approve dlsm to transfer weth
        weth.transfer(storer, 1e11);
        cheats.startPrank(storer);
        weth.approve(address(dataLayrPaymentManager), type(uint256).max);

        dataLayrPaymentManager.depositFutureFees(storer, 1e11);

        uint32 blockNumber = uint32(block.number);
        // change block number to 100 to avoid underflow in DataLayr (it calculates block.number - BLOCK_STALE_MEASURE)
        // and 'BLOCK_STALE_MEASURE' is currently 100
        cheats.roll(block.number + 100);
        cheats.warp(timeStampForInit);
        uint256 timestamp = block.timestamp;

        uint32 index = dlsm.initDataStore(
            storer,
            confirmer,
            header,
            durationToInit,
            totalBytes,
            blockNumber
        );

        bytes32 headerHash = keccak256(header);


        cheats.stopPrank();


        uint256 fee = calculateFee(totalBytes, 1, durationToInit);


        IDataLayrServiceManager.DataStoreMetadata
            memory metadata = IDataLayrServiceManager.DataStoreMetadata(
                headerHash,
                dlsm.getNumDataStoresForDuration(durationToInit)-1,
                dlsm.taskNumber() - 1,
                blockNumber,
                uint96(fee),
                confirmer,
                bytes32(0)
            );

        {
            bytes32 dataStoreHash = DataStoreHash.computeDataStoreHash(metadata);

            //check if computed hash matches stored hash in DLSM
            assertTrue(
                dataStoreHash ==
                    dlsm.getDataStoreHashesForDurationAtTimestamp(durationToInit, timestamp, index),
                "dataStore hashes do not match"
            );
        }
        
        searchData = IDataLayrServiceManager.DataStoreSearchData(
                durationToInit,
                timestamp,
                index,
                metadata
            );
        return searchData;
    }

    // deposits a fixed amount of eigen from address 'sender'
    // checks that the deposit is credited correctly
    function _testDepositEigen(address sender, uint256 toDeposit) public {
        // deposits will revert when amountToDeposit is 0
        cheats.assume(toDeposit > 0);
        eigenToken.transfer(sender, toDeposit);
        cheats.startPrank(sender);
        eigenToken.approve(address(investmentManager), type(uint256).max);

        uint256 eigenSharesBefore = investmentManager.investorStratShares(sender, eigenStrat);
        investmentManager.depositIntoStrategy(
            sender,
            eigenStrat,
            eigenToken,
            toDeposit
        );
        assertEq(
            investmentManager.investorStratShares(sender, eigenStrat),
            toDeposit + eigenSharesBefore,
            "_testDepositEigen: deposit not properly credited"
        );
        cheats.stopPrank();
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
        _testRegisterAsDelegate(sender, IDelegationTerms(sender));
        string memory socket = "255.255.255.255";

        cheats.startPrank(sender);
        
        dlReg.registerOperator(registrantType, ephemeralKey, data, socket);

        cheats.stopPrank();

        // verify that registration was stored correctly
        if ((registrantType & 1) == 1 && wethToDeposit > dlReg.nodeEthStake()) {
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
            (registrantType & 2) == 2 && eigenToDeposit > dlReg.nodeEigenStake()
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

    
    function _testConfirmDataStoreSelfOperators(uint8 signersInput) 
        internal 
        returns (bytes memory)
        {
        cheats.assume(signersInput > 0 && signersInput <= 15);

        uint32 numberOfSigners = uint32(signersInput);

        //register all the operators
        for (uint256 i = 0; i < numberOfSigners; ++i) {

            _testRegisterAdditionalSelfOperator(
                signers[i],
                registrationData[i]
            );
        }

        uint256 initTime = 1000000001;
        IDataLayrServiceManager.DataStoreSearchData memory searchData = _testInitDataStore(initTime, address(this));


        uint32 numberOfNonSigners = 0;
        (uint256 apk_0, uint256 apk_1, uint256 apk_2, uint256 apk_3) = getAggregatePublicKey(uint256(numberOfSigners));


        (uint256 sigma_0, uint256 sigma_1) = getSignature(uint256(numberOfSigners), 0);//(signatureData[0], signatureData[1]);
        
        
        /** 
     @param data This calldata is of the format:
            <
             bytes32 msgHash,
             uint48 index of the totalStake corresponding to the dataStoreId in the 'totalStakeHistory' array of the BLSRegistryWithBomb
             uint32 blockNumber
             uint32 dataStoreId
             uint32 numberOfNonSigners,
             uint256[numberOfNonSigners][4] pubkeys of nonsigners,
             uint32 apkIndex,
             uint256[4] apk,
             uint256[2] sigma
            >
     */
        bytes memory data = abi.encodePacked(
            keccak256(abi.encodePacked(searchData.metadata.globalDataStoreId, searchData.metadata.headerHash, searchData.duration, initTime, uint32(0))),
            uint48(dlReg.getLengthOfTotalStakeHistory() - 1),
            searchData.metadata.blockNumber,
            searchData.metadata.globalDataStoreId,
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

        
        dlsm.confirmDataStore(data, searchData);
        cheats.stopPrank();
        return data;
    }


    function _testConfirmDataStoreWithoutRegister(uint index, uint256 numSigners) internal {
        uint256 initTime = 1000000001;
        IDataLayrServiceManager.DataStoreSearchData
            memory searchData = _testInitDataStore(initTime, address(this));

        uint32 numberOfNonSigners = 0;
        (uint256 apk_0, uint256 apk_1, uint256 apk_2, uint256 apk_3) = getAggregatePublicKey(numSigners);
        (uint256 sigma_0, uint256 sigma_1) = getSignature(numSigners, index);//(signatureData[index*2], signatureData[2*index + 1]);


        /** 
     @param data This calldata is of the format:
            <
             bytes32 msgHash,
             uint48 index of the totalStake corresponding to the dataStoreId in the 'totalStakeHistory' array of the BLSRegistryWithBomb
             uint32 blockNumber
             uint32 dataStoreId
             uint32 numberOfNonSigners,
             uint256[numberOfSigners][4] pubkeys of nonsigners,
             uint32 apkIndex,
             uint256[4] apk,
             uint256[2] sigma
            >
     */
        

        bytes memory data = abi.encodePacked(
            keccak256(
                abi.encodePacked(searchData.metadata.globalDataStoreId, searchData.metadata.headerHash, searchData.duration, initTime, searchData.index)
            ),
            uint48(dlReg.getLengthOfTotalStakeHistory() - 1),
            searchData.metadata.blockNumber,
            searchData.metadata.globalDataStoreId,
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
        dlsm.confirmDataStore(data, searchData);
        emit log_named_uint("confirm gas overall", gasbefore - gasleft());

        // bytes32 sighash = dlsm.getDataStoreIdSignatureHash(
        //     dlsm.dataStoreId() - 1
        // );
        // assertTrue(sighash != bytes32(0), "Data store not committed");
        cheats.stopPrank();
    }

    // simply tries to register 'sender' as a delegate, setting their 'DelegationTerms' contract in EigenLayrDelegation to 'dt'
    // verifies that the storage of EigenLayrDelegation contract is updated appropriately
    function _testRegisterAsDelegate(address sender, IDelegationTerms dt)
        internal
    {
        
        cheats.startPrank(sender);
        delegation.registerAsDelegate(dt);
        assertTrue(delegation.isDelegate(sender), "testRegisterAsDelegate: sender is not a delegate");

        assertTrue(
            delegation.delegationTerms(sender) == dt,
            "_testRegisterAsDelegate: delegationTerms not set appropriately"
        );
        cheats.stopPrank();

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
            initialOperatorShares[i] = delegation.operatorShares(
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
            uint256 operatorSharesAfter = delegation.operatorShares(
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
        InvestmentStrategyBase strategy = new InvestmentStrategyBase(investmentManager);
        // deploying these as upgradeable proxies was causing a weird stack overflow error, so we're just using implementation contracts themselves for now
        // strategy = InvestmentStrategyBase(address(new TransparentUpgradeableProxy(address(strat), address(eigenLayrProxyAdmin), "")));
        strategy.initialize(weth);
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
            // check that strategy is appropriately added to dynamic array of all of sender's strategies
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
        delegation.initUndelegation();
        delegation.commitUndelegation();
        cheats.warp(block.timestamp + 365 days);
        delegation.finalizeUndelegation();
        cheats.stopPrank();
        assertTrue(delegation.isNotDelegated(sender)==true, "testDelegation: staker is not undelegated");
    }

    function calculateFee(
        uint32 totalBytes,
        uint256 feePerBytePerTime,
        uint256 duration
    ) internal pure returns (uint256) {
        return
            uint256(totalBytes * feePerBytePerTime * duration * DURATION_SCALE);
    }
    function testDeploymentSuccessful() public {
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
        assertTrue(address(weth) != address(0), "weth failed to deploy");
        assertTrue(address(dlsm) != address(0), "dlsm failed to deploy");
        assertTrue(address(dlReg) != address(0), "dlReg failed to deploy");
        assertTrue(
            address(dlRepository) != address(0),
            "dlRepository failed to deploy"
        );
        assertTrue(
            dlRepository.serviceManager() == dlsm,
            "ServiceManager set incorrectly"
        );
        assertTrue(
            dlsm.repository() == dlRepository,
            "repository set incorrectly in dlsm"
        );

    }


}
