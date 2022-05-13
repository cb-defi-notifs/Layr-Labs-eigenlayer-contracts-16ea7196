// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";


import "../contracts/interfaces/IDataLayrPaymentChallenge.sol";
import "../test/Deployer.t.sol";

import "../contracts/libraries/BytesLib.sol";

import "../contracts/middleware/ServiceManagerBase.sol";

import "ds-test/test.sol";

import "./utils/CheatCodes.sol";

contract Delegator is EigenLayrDeployer {
    using BytesLib for bytes;
    using Math for uint;
    uint shares;
    address[2] public delegators;
    bytes[] headers;
    ServiceManagerBase serviceManager;
    VoteWeigherBase voteWeigher;
    Repository repository;
    IRepository newRepository;
    ServiceFactory factory;
    IRegistrationManager regManager;
    IDataLayrPaymentChallenge dlpc;
    DelegationTerms dt;
    uint120 amountRewards;

    uint256 amountEigenToDeposit = 20;
    uint256 amountEthToDeposit = 2e19;
    address challenger = address(0x6966904396bF2f8b173350bCcec5007A52669873);
    address challengeContract;

    constructor(){
        delegators = [acct_0, acct_1];
        // headers.push(bytes("0x0102030405060708091011121314151617184567"));
        // headers.push(bytes("0x0102030405060708091011121314151617182167"));
        // headers.push(bytes("0x0102030405060708091011121314151617181920"));
        // headers.push(bytes("0x0102030405060708091011121314151617181934"));
        // headers.push(bytes("0x0102030405060708091011121314151617181956"));
        // headers.push(bytes("0x0102030405060708091011121314151617181967"));
        // headers.push(bytes("0x0102030405060708091011121314151617181909"));
        // headers.push(bytes("0x0102030405060708091011121314151617181944"));
        // headers.push(bytes("0x0102030405060708091011121314151617145620"));
    }

    function testSelfOperatorDelegate() public {
        _testSelfOperatorDelegate(signers[0]);
    }
    
    function testSelfOperatorRegister() public {
        _testRegisterAdditionalSelfOperator(registrant, registrationData[0]);
    }

    function testTwoSelfOperatorsRegister() public {
        address sender = acct_0;
        _testRegisterAdditionalSelfOperator(registrant, registrationData[0]);
        _testRegisterAdditionalSelfOperator(sender, registrationData[1]);
    }
    
    // registers a fixed address as a delegate, delegates to it from a second address, and checks that the delegate's voteWeights increase properly
    function testDelegation() public {
        uint96 registrantEthWeightBefore = uint96(
            dlReg.weightOfOperatorEth(registrant)
        );
        uint96 registrantEigenWeightBefore = uint96(
            dlReg.weightOfOperatorEigen(registrant)
        );
        DelegationTerms _dt = _deployDelegationTerms(registrant);
        _testRegisterAsDelegate(registrant, _dt);
        _testWethDeposit(acct_0, 1e18);
        _testDepositEigen(acct_0);
        _testDelegateToOperator(acct_0, registrant);

        uint96 registrantEthWeightAfter = uint96(
            dlReg.weightOfOperatorEth(registrant)
        );
        uint96 registrantEigenWeightAfter = uint96(
            dlReg.weightOfOperatorEigen(registrant)
        );
        assertTrue(
            registrantEthWeightAfter > registrantEthWeightBefore,
            "testDelegation: registrantEthWeight did not increase!"
        );
        assertTrue(
            registrantEigenWeightAfter > registrantEigenWeightBefore,
            "testDelegation: registrantEigenWeight did not increase!"
        );
        IInvestmentStrategy _strat = investmentManager.investorStrats(acct_0, 0);
        assertTrue(address(_strat) != address(0), "investorStrats not updated correctly");
        assertTrue(delegation.operatorShares(registrant, _strat) > 0, "operatorShares not updated correctly");
    }

    // registers a fixed address as a delegate, delegates to it from a second address, and checks that the delegate's voteWeights increase properly
    function testDelegationMultipleStrategies(uint16 numStratsToAdd) public {
        cheats.assume(numStratsToAdd > 0 && numStratsToAdd <= 20);
        uint96 registrantEthWeightBefore = uint96(
            dlReg.weightOfOperatorEth(registrant)
        );
        uint96 registrantEigenWeightBefore = uint96(
            dlReg.weightOfOperatorEigen(registrant)
        );
        DelegationTerms _dt = _deployDelegationTerms(registrant);

        _testRegisterAsDelegate(registrant, _dt);
        _testDepositStrategies(acct_0, 1e18, numStratsToAdd);
        _testDepositEigen(acct_0);

        // add all the new strategies to the 'strategiesConsidered' of dlVW
        IInvestmentStrategy[] memory strats = new IInvestmentStrategy[](numStratsToAdd);
        for (uint256 i = 0; i < strats.length; ++i) {
            strats[i] = strategies[i];
        }
        cheats.startPrank(address(dlReg.repository().timelock()));
        dlReg.addStrategiesConsidered(strats);
        cheats.stopPrank();

        _testDelegateToOperator(acct_0, registrant);
        uint96 registrantEthWeightAfter = uint96(
            dlReg.weightOfOperatorEth(registrant)
        );
        uint96 registrantEigenWeightAfter = uint96(
            dlReg.weightOfOperatorEigen(registrant)
        );
        assertTrue(
            registrantEthWeightAfter > registrantEthWeightBefore,
            "testDelegation: registrantEthWeight did not increase!"
        );
        assertTrue(
            registrantEigenWeightAfter > registrantEigenWeightBefore,
            "testDelegation: registrantEigenWeight did not increase!"
        );
        for (uint16 i = 0; i < numStratsToAdd; ++i) {
            IInvestmentStrategy depositorStrat = investmentManager.investorStrats(acct_0, i);
            assertTrue(
                delegation.operatorShares(registrant, depositorStrat)
                ==
                investmentManager.investorStratShares(acct_0, depositorStrat),
                "delegate shares not stored properly"
            );
        }
    }

    //TODO: add tests for contestDelegationCommit()
    function testUndelegation() public {
        //delegate
        DelegationTerms _dt = _deployDelegationTerms(registrant);
        _testRegisterAsDelegate(registrant, _dt);
        _testWethDeposit(acct_0, 1e18);
        _testDepositEigen(acct_0);
        _testDelegateToOperator(acct_0, registrant);

        //delegator-specific information
        (
            IInvestmentStrategy[] memory delegatorStrategies,
            uint256[] memory delegatorShares
        ) = investmentManager.getDeposits(msg.sender);

        //mapping(IInvestmentStrategy => uint256) memory initialOperatorShares;
        for (uint256 k = 0; k < delegatorStrategies.length; k++) {
            initialOperatorShares[delegatorStrategies[k]] = delegation
                .getOperatorShares(registrant, delegatorStrategies[k]);
        }

        _testUndelegation(acct_0);

        for (uint256 k = 0; k < delegatorStrategies.length; k++) {
            uint256 operatorSharesBefore = initialOperatorShares[
                delegatorStrategies[k]
            ];
            uint256 operatorSharesAfter = delegation.getOperatorShares(
                registrant,
                delegatorStrategies[k]
            );
            assertTrue(
                delegatorShares[k] == operatorSharesAfter - operatorSharesBefore
            );
        }
    }


    
    function testInitiateDelegation() public {        
        _testInitiateDelegation(1e10);
        emit log("c");

        //servicemanager pays out rewards to delegate and delegators
        _payRewards();
        
        
        // for(uint i; i < delegators.length; i++){
        //     (
        //     IInvestmentStrategy[] memory strategies,
        //     uint256[] memory shares
        // ) = investmentManager.getDeposits(delegators[i]);
        //     dt.onDelegationWithdrawn(delegators[i], strategies, shares);
        // }

    }

    function _testInitiateDelegation(uint256 amountToDeposit) public {
        //setting up operator's delegation terms
        address toRegister = signers[0];
        weth.transfer(toRegister, 1e5);
        weth.transfer(challenger, 1e5);
        cheats.startPrank(toRegister);
        dt = _setDelegationTerms(toRegister);
        cheats.stopPrank();        
        _testRegisterAsDelegate(toRegister, dt);

        for(uint i; i < delegators.length; i++){
            //initialize weth, eigen and eth balances for delegator
            eigen.safeTransferFrom(address(this), delegators[i], 0, amountEigenToDeposit, "0x");
            weth.transfer(delegators[i], amountToDeposit);
            cheats.deal(delegators[i], amountEthToDeposit);

            cheats.startPrank(delegators[i]);

            //depositing delegator's eth into consensus layer
            deposit.depositEthIntoConsensusLayer{value: amountEthToDeposit}("0x", "0x", depositContract.get_deposit_root());

            //deposit delegator's eigen into investment manager
            eigen.setApprovalForAll(address(investmentManager), true);
            investmentManager.depositEigen(amountEigenToDeposit);
            
            //depost weth into investment manager
            weth.approve(address(investmentManager), type(uint256).max);
            investmentManager.depositIntoStrategy(
                delegators[i],
                strat,
                weth,
                amountToDeposit);

            //delegate delegators deposits to operator
            delegation.delegateTo(toRegister);
            cheats.stopPrank();
        }

        cheats.startPrank(toRegister);
        //register operator with vote weigher so they can get payment
        cheats.stopPrank();

    }

    function _payRewards() internal {
        amountRewards = 10;

        //Operator submits claim to rewards
        _testCommitPayment(amountRewards);


        //initiate challenge
        challengeContract = _testInitPaymentChallenge(registrant, 5, 3);
        dlpc = IDataLayrPaymentChallenge(challengeContract);

        bool half = true;


        //Challenge payment test
        _operatorDisputesChallenger(registrant, half, 2, 3);
        _challengerDisputesOperator(registrant, half, 1, 1);
        _operatorDisputesChallenger(registrant, half, 1, 1);
        emit log_uint(dlpc.getDiff());
        emit log("c");


        //dlpc.respondToPaymentChallengeFinal();
        //dlpc.resolveChallenge();

        //_testPaymentChallenge(registrant, 5, 5, 5, 3);

    }
   
    //Challenger initiates the challenge to operator's claim
    // challenge status:  0: commited, 1: redeemed, 2: operator turn (dissection), 3: challenger turn (dissection)
    // 4: operator turn (one step), 5: challenger turn (one step)
    function _testPaymentChallenge(
        address operator, 
        uint120 operatorAmount1, 
        uint120 operatorAmount2, 
        uint120 challengerAmount1, 
        uint120 challengerAmount2
        ) internal{

        //The challenger has initiated a challenge to the payment commit of the operator
        //The next step is for the operator to respond to the proposed split of the challenger
        //This back and forth continues until there is resolution

        uint120 challengerTotal = challengerAmount1 + challengerAmount2;
        uint120 operatorTotal = operatorAmount1 + operatorAmount2;

        bool half = operatorAmount1 != challengerAmount1 ? false : true;

    }

    function _operatorDisputesChallenger(address operator, bool half, uint120 amount1, uint120 amount2) internal{

        cheats.startPrank(operator);
        if (dlpc.getDiff() == 1){
            emit log("HIT OPERATOR DIFF 1");
            return;
        }

        dlpc.challengePaymentHalf(half, amount1, amount2);
        cheats.stopPrank();

        //Now we calculate the challenger's response amounts
    }

    // function _challengerDisputesOperator(address operator, bool half, uint120 amount1, uint120 amount2) internal{
    function _challengerDisputesOperator(address, bool half, uint120 amount1, uint120 amount2) internal{
        cheats.startPrank(challenger);
        if (dlpc.getDiff() == 1){
            emit log("HIT OPERChallenger ATOR DIFF1");
            return;
        }
        dlpc.challengePaymentHalf(half, amount1, amount2);
        cheats.stopPrank();

    }

    //initiates the payment challenge from the challenger, with split that the challenger thinks is correct
    function _testInitPaymentChallenge(address operator, uint120 amount1, uint120 amount2) internal returns(address){
        cheats.startPrank(challenger);
        weth.approve(address(dlsm), type(uint256).max);

        //challenger initiates challenge
        dlsm.challengePaymentInit(operator, amount1, amount2);
        address _challengeContract = dlsm.operatorToPaymentChallenge(operator);
        cheats.stopPrank();

        return _challengeContract;
    }



     //Operator submits claim or commit for a payment amount
    function _testCommitPayment(uint120 _amountRewards) internal {
        emit log_named_uint("where is this broken", 0);
        // TODO: fix this here. currently this registers every operator as a self operator, and we register signers[0]
        //      as a delegate (not a self operator) within '_testConfirmDataStoreSelfOperators'
        _testConfirmDataStoreSelfOperators(15);
        emit log_named_uint("where is this broken", 1);

        cheats.startPrank(registrant);
        weth.approve(address(dlsm), type(uint256).max);
        uint32 currentDumpNumber = dlsm.dumpNumber() - 1;

        dlsm.commitPayment(currentDumpNumber, _amountRewards);
        cheats.stopPrank();
        //assertTrue(weth.balanceOf(address(dt)) == currBalance + amountRewards, "rewards not transferred to delegation terms contract");
    }

    //initialize delegation terms contract
    function _setDelegationTerms(address operator) internal returns (DelegationTerms) {
        address[] memory paymentTokens = new address[](0);
        uint16 _MAX_OPERATOR_FEE_BIPS = 500;
        uint16 _operatorFeeBips = 500;
        dt = 
            new DelegationTerms(
                operator,
                investmentManager,
                paymentTokens,
                factory,
                address(delegation),
                dlRepository,
                _MAX_OPERATOR_FEE_BIPS,
                _operatorFeeBips
            );
        assertTrue(address(dt) != address(0), "_deployDelegationTerms: DelegationTerms failed to deploy");
        dt.addPaymentToken(address(weth));
        return dt;

    }

}