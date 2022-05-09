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

import "./CheatCodes.sol";

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
        setUp();
        headers.push(bytes("0x0102030405060708091011121314151617184567"));
        headers.push(bytes("0x0102030405060708091011121314151617182167"));
        headers.push(bytes("0x0102030405060708091011121314151617181920"));
        headers.push(bytes("0x0102030405060708091011121314151617181934"));
        headers.push(bytes("0x0102030405060708091011121314151617181956"));
        headers.push(bytes("0x0102030405060708091011121314151617181967"));
        headers.push(bytes("0x0102030405060708091011121314151617181909"));
        headers.push(bytes("0x0102030405060708091011121314151617181944"));
        headers.push(bytes("0x0102030405060708091011121314151617145620"));


    }

    function testinitiateDelegation() public {

        //_initializeServiceManager();
        
        _testinitiateDelegation(1e10);

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
    function _testinitiateDelegation(uint256 amountToDeposit) public {
        //setting up operator's delegation terms
        weth.transfer(registrant, 1e5);
        weth.transfer(challenger, 1e5);
        cheats.startPrank(registrant);
        dt = _setDelegationTerms(registrant);
        delegation.registerAsDelegate(dt);
        cheats.stopPrank();        
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
            delegation.delegateTo(registrant);
            cheats.stopPrank();
        }

        cheats.startPrank(registrant);
        uint8 registrantType = 3;
        string memory socket = "fe";

        //register operator with vote weigher so they can get payment
        bytes memory data = registrationData[0];
        dlRegVW.registerOperator(registrantType, data, socket);
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

    function _challengerDisputesOperator(address operator, bool half, uint120 amount1, uint120 amount2) internal{
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
        address challengeContract = dlsm.operatorToPaymentChallenge(operator);
        cheats.stopPrank();

        return challengeContract;
    }



     //Operator submits claim or commit for a payment amount
    function _testCommitPayment(uint120 amountRewards) internal {


        //make 40 different data commits to DL
        for (uint i=0; i<9; i++){
            weth.transfer(storer, 10e10);
            cheats.prank(storer);
            weth.approve(address(dlsm), type(uint256).max);
            cheats.prank(storer);

            dlsm.initDataStore(
                headers[i],
                1e6,
                600
            );

            bytes storage data = registrationData[0];
            bytes32 headerHash = keccak256(headers[i]);
            (
                uint32 dataStoreDumpNumber,
                uint32 dataStoreInitTime,
                uint32 dataStorePeriodLength,
                bool dataStoreCommitted
            ) = dl.dataStores(headerHash);
            cheats.startPrank(registrant);
            weth.approve(address(dlsm), type(uint256).max);

            uint256 currBalance = weth.balanceOf(address(dt));
            dlsm.commitPayment(dataStoreDumpNumber, amountRewards);
            cheats.stopPrank();
        }
        
       

        

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