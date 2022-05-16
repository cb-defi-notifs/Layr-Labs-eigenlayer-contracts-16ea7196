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
    address[2] public delegators;
    bytes[] public headers;
    IDataLayrPaymentChallenge public dlpc;
    DelegationTerms public dt;

    uint256 public amountEigenToDeposit = 20;
    uint256 public amountEthToDeposit = 2e19;
    address public challenger = address(0x6966904396bF2f8b173350bCcec5007A52669873);
    address public challengeContract;
    mapping(IInvestmentStrategy => uint256) public initialOperatorShares;

    constructor(){
        delegators = [acct_0, acct_1];
    }

    function testSelfOperatorDelegate() public {
        _testSelfOperatorDelegate(signers[0]);
    }
    
    function testSelfOperatorRegister() public {
        _testRegisterAdditionalSelfOperator(signers[0], registrationData[0]);
    }

    function testTwoSelfOperatorsRegister() public {
        _testRegisterAdditionalSelfOperator(signers[0], registrationData[0]);
        _testRegisterAdditionalSelfOperator(signers[1], registrationData[1]);
    }
    
    // registers a fixed address as a delegate, delegates to it from a second address, and checks that the delegate's voteWeights increase properly
    function testDelegation() public {
        uint96 registrantEthWeightBefore = uint96(
            dlReg.weightOfOperatorEth(signers[0])
        );
        uint96 registrantEigenWeightBefore = uint96(
            dlReg.weightOfOperatorEigen(signers[0])
        );
        DelegationTerms _dt = _deployDelegationTerms(signers[0]);
        _testRegisterAsDelegate(signers[0], _dt);
        _testWethDeposit(acct_0, 1e18);
        _testDepositEigen(acct_0);
        _testDelegateToOperator(acct_0, signers[0]);

        uint96 registrantEthWeightAfter = uint96(
            dlReg.weightOfOperatorEth(signers[0])
        );
        uint96 registrantEigenWeightAfter = uint96(
            dlReg.weightOfOperatorEigen(signers[0])
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
        assertTrue(delegation.operatorShares(signers[0], _strat) > 0, "operatorShares not updated correctly");
    }

    // registers a fixed address as a delegate, delegates to it from a second address, and checks that the delegate's voteWeights increase properly
    function testDelegationMultipleStrategies(uint16 numStratsToAdd) public {
        cheats.assume(numStratsToAdd > 0 && numStratsToAdd <= 20);
        uint96 registrantEthWeightBefore = uint96(
            dlReg.weightOfOperatorEth(signers[0])
        );
        uint96 registrantEigenWeightBefore = uint96(
            dlReg.weightOfOperatorEigen(signers[0])
        );
        DelegationTerms _dt = _deployDelegationTerms(signers[0]);

        _testRegisterAsDelegate(signers[0], _dt);
        _testDepositStrategies(signers[1], 1e18, numStratsToAdd);
        _testDepositEigen(signers[1]);

        // add all the new strategies to the 'strategiesConsidered' of dlVW
        IInvestmentStrategy[] memory strats = new IInvestmentStrategy[](numStratsToAdd);
        for (uint256 i = 0; i < strats.length; ++i) {
            strats[i] = strategies[i];
        }
        cheats.startPrank(address(dlReg.repository().timelock()));
        dlReg.addStrategiesConsidered(strats);
        cheats.stopPrank();

        _testDelegateToOperator(signers[1], signers[0]);
        uint96 registrantEthWeightAfter = uint96(
            dlReg.weightOfOperatorEth(signers[0])
        );
        uint96 registrantEigenWeightAfter = uint96(
            dlReg.weightOfOperatorEigen(signers[0])
        );
        assertTrue(
            registrantEthWeightAfter > registrantEthWeightBefore,
            "testDelegation: registrantEthWeight did not increase!"
        );
        assertTrue(
            registrantEigenWeightAfter > registrantEigenWeightBefore,
            "testDelegation: registrantEigenWeight did not increase!"
        );
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


    
    function testRewardPayouts() public {        
        address operator = signers[0];
        _testInitiateDelegation(operator, 1e10);
        _payRewards(operator);
    }

    function _testInitiateDelegation(address operator, uint256 amountToDeposit) public {
        //setting up operator's delegation terms
        weth.transfer(operator, 1e5);
        weth.transfer(challenger, 1e5);
        dt = _deployDelegationTerms(operator);
        _testRegisterAsDelegate(operator, dt);

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

            cheats.stopPrank();

            //delegate delegator's deposits to operator
            _testDelegateToOperator(delegators[i], operator);
        }

        cheats.startPrank(operator);
        //register operator with vote weigher so they can get payment
        uint8 registrantType = 3;
        string memory socket = "255.255.255.255";
        // function registerOperator(uint8 registrantType, bytes calldata data, string calldata socket)
        dlReg.registerOperator(registrantType, registrationData[0], socket);
        cheats.stopPrank();

    }

    function _payRewards(address operator) internal {
        uint120 amountRewards = 10;

        //Operator submits claim to rewards
        _testCommitPayment(operator, amountRewards);


        //initiate challenge
        challengeContract = _testInitPaymentChallenge(operator, 5, 3);
        dlpc = IDataLayrPaymentChallenge(challengeContract);

        bool half = true;


        //Challenge payment test
        operatorDisputesChallenger(operator, half, 2, 3);
        challengerDisputesOperator(operator, half, 1, 1);
        operatorDisputesChallenger(operator, half, 1, 1);
        emit log_uint(dlpc.getDiff());

    }

    function operatorDisputesChallenger(address operator, bool half, uint120 amount1, uint120 amount2) public{

        cheats.startPrank(operator);
        if (dlpc.getDiff() == 1){
            emit log("Difference in dumpnumbers is now 1");
            cheats.stopPrank();
            return;
        }

        dlpc.challengePaymentHalf(half, amount1, amount2);
        cheats.stopPrank();

        //Now we calculate the challenger's response amounts
    }

    // function _challengerDisputesOperator(address operator, bool half, uint120 amount1, uint120 amount2) internal{
    function challengerDisputesOperator(address, bool half, uint120 amount1, uint120 amount2) public{
        cheats.startPrank(challenger);
        if (dlpc.getDiff() == 1){
            emit log("Difference in dumpnumbers is now");
            cheats.stopPrank();
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
    function _testCommitPayment(address operator, uint120 _amountRewards) internal {
        uint32 numberOfSigners = 15;

        //register all the operators
        //skip i = 0 since we have already registered signers[0] !!
        for (uint256 i = 1; i < numberOfSigners; ++i) {
            // emit log_named_uint("i", i);
            _testRegisterAdditionalSelfOperator(
                signers[i],
                registrationData[i]
            );
        }
    // scoped block helps fix 'stack too deep' errors
    {
        bytes32 headerHash = _testInitDataStore();
        uint32 currentDumpNumber = dlsm.dumpNumber() - 1;
        uint32 numberOfNonSigners = 0;
        (uint256 apk_0, uint256 apk_1, uint256 apk_2, uint256 apk_3) = (
            uint256(20820493588973199354272631301248587752629863429201347184003644368113679196121),
            uint256(18507428821816114421698399069438744284866101909563082454551586195885282320634),
            uint256(1263326262781780932600377484793962587101562728383804037421955407439695092960),
            uint256(3512517006108887301063578607317108977425754510174956792003926207778790018672)
        );
        (uint256 sigma_0, uint256 sigma_1) = (
            uint256(7155561537864411538991615376457474334371827900888029310878886991084477170996),
            uint256(10352977531892356631551102769773992282745949082157652335724669165983475588346)
        );

    /** 
     @param data This calldata is of the format:
            <
             uint32 dumpNumber,
             bytes32 headerHash,
             uint48 index of the totalStake corresponding to the dumpNumber in the 'totalStakeHistory' array of the DataLayrRegistry
             uint32 numberOfNonSigners,
             uint256[numberOfSigners][4] pubkeys of nonsigners,
             uint32 apkIndex,
             uint256[4] apk,
             uint256[2] sigma
            >
     */
    
        bytes memory data = abi.encodePacked(
            currentDumpNumber,
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

        dlsm.confirmDataStore(data);
        (, , , bool committed) = dl.dataStores(headerHash);
        assertTrue(committed, "Data store not committed");
    }
        cheats.stopPrank();

        // // try initing another dataStore, so currentDumpNumber > fromDumpNumber
        // _testInitDataStore();
        bytes memory header = hex"0102030405060708091011121314151617181921";
        uint32 totalBytes = 1e6;
        uint32 storePeriodLength = 600;

        //weth is set as the paymentToken of dlsm, so we must approve dlsm to transfer weth
        weth.transfer(storer, 10e10);
        cheats.startPrank(storer);
        weth.approve(address(dlsm), type(uint256).max);
        dlsm.initDataStore(header, totalBytes, storePeriodLength);
        cheats.stopPrank();


        cheats.startPrank(operator);
        weth.approve(address(dlsm), type(uint256).max);

        // uint256 fromDumpNumber = IDataLayrRegistry(address(dlsm.repository().voteWeigher())).getOperatorFromDumpNumber(operator);
        uint32 newCurrentDumpNumber = dlsm.dumpNumber() - 1;
        dlsm.commitPayment(newCurrentDumpNumber, _amountRewards);
        cheats.stopPrank();
        //assertTrue(weth.balanceOf(address(dt)) == currBalance + amountRewards, "rewards not transferred to delegation terms contract");
    }
}