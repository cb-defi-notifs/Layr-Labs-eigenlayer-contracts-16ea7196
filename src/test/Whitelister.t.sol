// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../src/contracts/interfaces/IInvestmentManager.sol";
import "../../src/contracts/interfaces/IInvestmentStrategy.sol";
import "../../src/contracts/interfaces/IEigenLayrDelegation.sol";
import "../../src/contracts/strategies/InvestmentStrategyBase.sol";
import "../../src/contracts/middleware/BLSRegistry.sol";

import "../../src/test/mocks/ServiceManagerMock.sol";
import "../../src/test/mocks/PublicKeyCompendiumMock.sol";
import "../../src/test/mocks/MiddlewareVoteWeigherMock.sol";



import "../../script/whitelist/ERC20PresetMinterPauser.sol";

import "../../script/whitelist/Staker.sol";
import "../../script/whitelist/Whitelister.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

import "./EigenLayrTestHelper.t.sol";
import "./Delegation.t.sol";

import "forge-std/Test.sol";

contract WhitelisterTests is EigenLayrTestHelper {

    ERC20PresetMinterPauser dummyToken;
    IInvestmentStrategy dummyStrat;
    IInvestmentStrategy dummyStratImplementation;
    Whitelister whiteLister;

    BLSRegistry blsRegistry;
    BLSRegistry blsRegistryImplementation;


    ServiceManagerMock dummyServiceManager;
    BLSPublicKeyCompendiumMock dummyCompendium;

    MiddlewareVoteWeigherMock public voteWeigher;
    MiddlewareVoteWeigherMock public voteWeigherImplementation;



    uint256 DEFAULT_AMOUNT = 10e18;

    // packed info used to help handle stack-too-deep errors
    struct DataForTestWithdrawal {
        IInvestmentStrategy[] delegatorStrategies;
        uint256[] delegatorShares;
        IInvestmentManager.WithdrawerAndNonce withdrawerAndNonce;
    }

    address theMultiSig = address(420);

    function setUp() public virtual override{
        EigenLayrDeployer.setUp();


        emptyContract = new EmptyContract();

        dummyCompendium = new BLSPublicKeyCompendiumMock();
        blsRegistry = BLSRegistry(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );
        voteWeigher = MiddlewareVoteWeigherMock(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );

        dummyToken = new ERC20PresetMinterPauser("dummy staked ETH", "dsETH");
        dummyStratImplementation = new InvestmentStrategyBase(investmentManager);
        dummyStrat = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                        address(dummyStratImplementation),
                        address(eigenLayrProxyAdmin),
                        abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, dummyToken, eigenLayrPauserReg)
                    )
                )
        );

        whiteLister = new Whitelister(investmentManager, delegation, dummyToken, dummyStrat, blsRegistry);
        whiteLister.transferOwnership(theMultiSig);

        dummyToken.grantRole(keccak256("MINTER_ROLE"), address(whiteLister));
        dummyToken.grantRole(keccak256("PAUSER_ROLE"), address(whiteLister));  

        dummyToken.grantRole(keccak256("MINTER_ROLE"), theMultiSig);
        dummyToken.grantRole(keccak256("PAUSER_ROLE"), theMultiSig);

        dummyToken.revokeRole(keccak256("MINTER_ROLE"), address(this));  
        dummyToken.revokeRole(keccak256("PAUSER_ROLE"), address(this));  


        dummyServiceManager  = new ServiceManagerMock(investmentManager);
        blsRegistryImplementation = new BLSRegistry(delegation, investmentManager, dummyServiceManager, 2, dummyCompendium);
        voteWeigherImplementation = new MiddlewareVoteWeigherMock(delegation, investmentManager, dummyServiceManager);

        uint256[] memory _quorumBips = new uint256[](2);
        // split 60% ETH quorum, 40% EIGEN quorum
        _quorumBips[0] = 6000;
        _quorumBips[1] = 4000;

        VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[] memory ethStratsAndMultipliers =
                new VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[](1);
            ethStratsAndMultipliers[0].strategy = wethStrat;
            ethStratsAndMultipliers[0].multiplier = 1e18;
        VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[] memory eigenStratsAndMultipliers =
                new VoteWeigherBaseStorage.StrategyAndWeightingMultiplier[](1);
            eigenStratsAndMultipliers[0].strategy = eigenStrat;
            eigenStratsAndMultipliers[0].multiplier = 1e18;

        eigenLayrProxyAdmin.upgradeAndCall(
                TransparentUpgradeableProxy(payable(address(blsRegistry))),
                address(blsRegistryImplementation),
                abi.encodeWithSelector(BLSRegistry.initialize.selector, address(whiteLister), true, _quorumBips, ethStratsAndMultipliers, eigenStratsAndMultipliers)
            );
        eigenLayrProxyAdmin.upgradeAndCall(
                TransparentUpgradeableProxy(payable(address(voteWeigher))),
                address(voteWeigherImplementation),
                abi.encodeWithSelector(MiddlewareVoteWeigherMock.initialize.selector, _quorumBips, ethStratsAndMultipliers, eigenStratsAndMultipliers)
            );

    }

    function testWhitelistingOperator(address operator) public fuzzedAddress(operator){
        cheats.startPrank(operator);
        IDelegationTerms dt = IDelegationTerms(address(89));
        delegation.registerAsOperator(dt);
        cheats.stopPrank();

        cheats.startPrank(theMultiSig);
        whiteLister.whitelist(operator);
        cheats.stopPrank();

        assertTrue(blsRegistry.whitelisted(operator) == true, "operator not added to whitelist");
    }

    function testDepositIntoStrategy(address operator, uint256 amount) external fuzzedAddress(operator){
        cheats.assume(amount < DEFAULT_AMOUNT);
        testWhitelistingOperator(operator);

        cheats.startPrank(theMultiSig);
        address staker = whiteLister.getStaker(operator);
        dummyToken.mint(staker, DEFAULT_AMOUNT);

        whiteLister.depositIntoStrategy(staker, dummyStrat, dummyToken, amount);
        cheats.stopPrank();
    }

    function testQueueWithdrawal(
            address operator, 
            address staker,
            address withdrawer, 
            uint256 ethAmount,
            uint256 eigenAmount,
            bool withdrawAsTokens,
            string calldata socket
        ) 
            external  fuzzedAddress(operator) fuzzedAddress(staker)
        {
        cheats.assume(operator != staker);
        _testRegisterAsOperator(operator, IDelegationTerms(operator));
        _testDepositWeth(staker, ethAmount);
        _testDepositEigen(staker, eigenAmount);
        _testDelegateToOperator(staker, operator);
        assertTrue(delegation.isDelegated(staker) == true, "testDelegation: staker is not delegate");


        cheats.startPrank(operator);
        slasher.optIntoSlashing(address(dummyServiceManager));
        cheats.stopPrank();


        // BN254.G1Point memory pk = getOperatorPubkeyG1(0);

        BN254.G1Point memory pk = getOperatorPubkeyG1(0);

        //register as both ETH and EIGEN operator
        
        cheats.startPrank(theMultiSig);
        whiteLister.whitelist(operator);
        cheats.stopPrank();

        cheats.startPrank(operator);
                emit log("ss");
                emit log("ss");

        dummyCompendium.registerPublicKey(pk);
                        emit log("ss");


        blsRegistry.registerOperator(0, pk, socket);


    //     // address delegatedTo = delegation.delegatedTo(staker);

    //     // // packed data structure to deal with stack-too-deep issues
    //     // DataForTestWithdrawal memory dataForTestWithdrawal;

    //     // // scoped block to deal with stack-too-deep issues
    //     // {
    //     //     //delegator-specific information
    //     //     (IInvestmentStrategy[] memory delegatorStrategies, uint256[] memory delegatorShares) =
    //     //         investmentManager.getDeposits(staker);
    //     //     dataForTestWithdrawal.delegatorStrategies = delegatorStrategies;
    //     //     dataForTestWithdrawal.delegatorShares = delegatorShares;

    //     //     IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce = 
    //     //         IInvestmentManager.WithdrawerAndNonce({
    //     //             withdrawer: withdrawer,
    //     //             // harcoded nonce value
    //     //             nonce: 0
    //     //         }
    //     //     );
    //     //     dataForTestWithdrawal.withdrawerAndNonce = withdrawerAndNonce;
    //     // }

    //     // uint256[] memory strategyIndexes = new uint256[](2);
    //     // IERC20[] memory tokensArray = new IERC20[](2);
    //     // {
    //     //     // hardcoded values
    //     //     strategyIndexes[0] = 0;
    //     //     strategyIndexes[1] = 0;
    //     //     tokensArray[0] = weth;
    //     //     tokensArray[1] = eigenToken;
    //     // }

    //     // cheats.warp(uint32(block.timestamp) + 1 days);
    //     // cheats.roll(uint32(block.timestamp) + 1 days);

    //     // _testQueueWithdrawal(
    //     //     staker,
    //     //     dataForTestWithdrawal.delegatorStrategies,
    //     //     tokensArray,
    //     //     dataForTestWithdrawal.delegatorShares,
    //     //     strategyIndexes,
    //     //     withdrawer
    //     // );
    //     // uint32 queuedWithdrawalBlock = uint32(block.number);
        
    //     // //now withdrawal block time is before deregistration
    //     // cheats.warp(uint32(block.timestamp) + 2 days);
    //     // cheats.roll(uint32(block.timestamp) + 2 days);
        
    //     // generalReg1.deregisterOperator(operator);
    //     // {
    //     //     //warp past the serve until time, which is 3 days from the beginning.  THis puts us at 4 days past that point
    //     //     cheats.warp(uint32(block.timestamp) + 4 days);
    //     //     cheats.roll(uint32(block.timestamp) + 4 days);

    //     //     uint256 middlewareTimeIndex =  1;
    //     //     if (withdrawAsTokens) {
    //     //         _testCompleteQueuedWithdrawalTokens(
    //     //             depositor,
    //     //             dataForTestWithdrawal.delegatorStrategies,
    //     //             tokensArray,
    //     //             dataForTestWithdrawal.delegatorShares,
    //     //             delegatedTo,
    //     //             dataForTestWithdrawal.withdrawerAndNonce,
    //     //             queuedWithdrawalBlock,
    //     //             middlewareTimeIndex
    //     //         );
    //     //     } else {
    //     //         _testCompleteQueuedWithdrawalShares(
    //     //             depositor,
    //     //             dataForTestWithdrawal.delegatorStrategies,
    //     //             tokensArray,
    //     //             dataForTestWithdrawal.delegatorShares,
    //     //             delegatedTo,
    //     //             dataForTestWithdrawal.withdrawerAndNonce,
    //     //             queuedWithdrawalBlock,
    //     //             middlewareTimeIndex
    //     //         );
    //     //     }
    //     // }
    }

    function _testQueueWithdrawal(
        address staker,
        IInvestmentStrategy[] memory strategyArray,
        IERC20[] memory tokensArray,
        uint256[] memory shareAmounts,
        uint256[] memory strategyIndexes,
        address withdrawer
    )
        internal
        returns (bytes32)
    {
        cheats.startPrank(theMultiSig);

        whiteLister.queueWithdrawal(
            staker,
            strategyIndexes,
            strategyArray,
            tokensArray,
            shareAmounts,
            withdrawer,
            true
        );
        cheats.stopPrank();
    }


    function registerOperator(address operator, uint32 operatorIndex, string calldata socket) public fuzzedAddress(operator){
        cheats.assume(operatorIndex < 15);
        BN254.G1Point memory pk = getOperatorPubkeyG1(operatorIndex);

        //register as both ETH and EIGEN operator
        
        cheats.startPrank(operator);
        dummyCompendium.registerPublicKey(pk);
        blsRegistry.registerOperator(1, pk, socket);
        cheats.stopPrank();

        bytes32 pubkeyHash = BN254.hashG1Point(pk);
        
        (uint32 toBlockNumber, uint32 index) = blsRegistry.pubkeyHashToIndexHistory(pubkeyHash,0);

        assertTrue(toBlockNumber == 0, "block number set when it shouldn't be");
        assertTrue(index == 0, "index has been set incorrectly");
        assertTrue(blsRegistry.operatorList(0) == operator, "incorrect operator added");
    }

}