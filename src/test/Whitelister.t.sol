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
    MiddlewareRegistryMock dummyReg;

    MiddlewareVoteWeigherMock public voteWeigher;
    MiddlewareVoteWeigherMock public voteWeigherImplementation;
    address withdrawer = address(345);
    

    modifier fuzzedAmounts(uint256 ethAmount, uint256 eigenAmount){
        cheats.assume(ethAmount >= 0 && ethAmount <= 1e18);
        cheats.assume(eigenAmount >= 0 && eigenAmount <= 1e18);
        _;
    }




    uint256 amount;

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
        amount = whiteLister.DEFAULT_AMOUNT();

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
        
        dummyReg = new MiddlewareRegistryMock(
             dummyServiceManager,
             investmentManager
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

    function testDepositIntoStrategy(address operator, uint256 depositAmount) external fuzzedAddress(operator){
        cheats.assume(depositAmount < amount);
        testWhitelistingOperator(operator);

        cheats.startPrank(theMultiSig);
        address staker = whiteLister.getStaker(operator);
        dummyToken.mint(staker, amount);

        whiteLister.depositIntoStrategy(staker, dummyStrat, dummyToken, depositAmount);
        cheats.stopPrank();
    }

    function testQueueWithdrawal(
            address operator, 
            string calldata socket
        ) 
            external  fuzzedAddress(operator)
        {

        address staker = whiteLister.getStaker(operator);
        cheats.assume(staker!=operator);
        _testRegisterAsOperator(operator, IDelegationTerms(operator));

        {
            // cheats.startPrank(operator);
            // slasher.optIntoSlashing(address(dummyServiceManager));
            // cheats.stopPrank();
                    emit log("*******whiteLister.depositIntoStrategy***********");

            cheats.startPrank(theMultiSig);
            whiteLister.whitelist(operator);
                    emit log("*******whiteLister.depositIntoStrategy***********");

                    emit log("*******whiteLister.depositIntoStrategy***********");

            
            //whiteLister.depositIntoStrategy(staker, dummyStrat, dummyToken, amount);
            cheats.stopPrank();

            cheats.startPrank(operator);
            slasher.optIntoSlashing(address(dummyServiceManager));
            dummyReg.registerOperator(operator, uint32(block.timestamp) + 3 days);
            cheats.stopPrank();
        }

        // packed data structure to deal with stack-too-deep issues
        DataForTestWithdrawal memory dataForTestWithdrawal;

        // scoped block to deal with stack-too-deep issues
        {
            //delegator-specific information
            (IInvestmentStrategy[] memory delegatorStrategies, uint256[] memory delegatorShares) =
                investmentManager.getDeposits(staker);
            dataForTestWithdrawal.delegatorStrategies = delegatorStrategies;
            dataForTestWithdrawal.delegatorShares = delegatorShares;

            IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce = 
                IInvestmentManager.WithdrawerAndNonce({
                    withdrawer: staker,
                    // harcoded nonce value
                    nonce: 0
                }
            );
            dataForTestWithdrawal.withdrawerAndNonce = withdrawerAndNonce;
        }

        uint256[] memory strategyIndexes = new uint256[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        {
            // hardcoded values
            strategyIndexes[0] = 0;
            tokensArray[0] = dummyToken;
        }

        _testQueueWithdrawal(
            staker,
            dataForTestWithdrawal.delegatorStrategies,
            tokensArray,
            dataForTestWithdrawal.delegatorShares,
            strategyIndexes
        );

        {
            uint256 balanceBeforeWithdrawal = dummyToken.balanceOf(staker);
            //warp past the serve until time, which is 3 days from the beginning.  THis puts us at 4 days past that point
            // cheats.warp(uint32(block.timestamp) + 4 days);
            // cheats.roll(uint32(block.timestamp) + 4 days);

            _testCompleteQueuedWithdrawal(
                staker,
                dataForTestWithdrawal.delegatorStrategies,
                tokensArray,
                dataForTestWithdrawal.delegatorShares,
                operator,
                dataForTestWithdrawal.withdrawerAndNonce,
                uint32(block.number),
                1
            );
                        emit log_named_uint("dummyToken.balanceOf(staker)", dummyToken.balanceOf(staker));
            emit log_named_uint("balanceBeforeWithdrawal", balanceBeforeWithdrawal);
        
            require(dummyToken.balanceOf(staker) == balanceBeforeWithdrawal + amount, "balance not incremented");

        }
        // uint256 balanceAfterWithdrawal = dummyToken.balanceOf(staker);
        // emit log_uint(balanceAfterWithdrawal);
        

    }
    function _testQueueWithdrawal(
        address staker,
        IInvestmentStrategy[] memory strategyArray,
        IERC20[] memory tokensArray,
        uint256[] memory shareAmounts,
        uint256[] memory strategyIndexes
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
            staker,
            true
        );
        cheats.stopPrank();
    }

     function _testCompleteQueuedWithdrawal(
        address staker,
        IInvestmentStrategy[] memory strategyArray,
        IERC20[] memory tokensArray,
        uint256[] memory shareAmounts,
        address delegatedTo,
        IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce,
        uint32 withdrawalStartBlock,
        uint256 middlewareTimesIndex
    )
        internal
    {
        IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal = IInvestmentManager.QueuedWithdrawal({
            strategies: strategyArray,
            tokens: tokensArray,
            shares: shareAmounts,
            depositor: staker,
            withdrawerAndNonce: withdrawerAndNonce,
            withdrawalStartBlock: withdrawalStartBlock,
            delegatedAddress: delegatedTo
        });

         emit log("***********************************************************************");
        emit log_named_address("delegatedAddress", delegatedTo);
        emit log_named_uint("withdrawalStartBlock", withdrawalStartBlock);
        emit log_named_uint("withdrawerAndNonce.Nonce", withdrawerAndNonce.nonce);
        emit log_named_address("withdrawerAndNonce.Adress", withdrawerAndNonce.withdrawer);
        emit log_named_address("depositor", staker);
         emit log("***********************************************************************");




        cheats.startPrank(theMultiSig);
        // complete the queued withdrawal
        whiteLister.completeQueuedWithdrawal(staker, queuedWithdrawal, middlewareTimesIndex, true);
        cheats.stopPrank();
    }





}