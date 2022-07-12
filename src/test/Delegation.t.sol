// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";


import "../contracts/interfaces/IDataLayrPaymentManager.sol";
import "../contracts/interfaces/ISlasher.sol";
import "../test/Deployer.t.sol";

import "../contracts/libraries/BytesLib.sol";

import "../contracts/middleware/ServiceManagerBase.sol";

import "../contracts/middleware/DataLayr/DataLayrPaymentManager.sol";

contract Delegator is EigenLayrDeployer {
    using BytesLib for bytes;
    using Math for uint;
    uint shares;
    address[2] public delegates;
    bytes[] headers;
    uint256[] apks; 
    uint256[] sigmas;
    ServiceManagerBase serviceManager;
    VoteWeigherBase voteWeigher;
    Repository repository;
    IRepository newRepository;
    ServiceFactory factory;
    IRegistry regManager;
    //ISlasher slasher;
    DelegationTerms dt;

    uint256 amountEigenToDeposit = 20;
    uint256 amountEthToDeposit = 2e19;
    address _challenger = address(0x6966904396bF2f8b173350bCcec5007A52669873);
    address challengeContract;
    mapping(IInvestmentStrategy => uint256) public initialOperatorShares;

    struct nonSignerInfo{
        uint256 xA0;
        uint256 xA1;
        uint256 yA0;
        uint256 yA1;
    }

    struct signerInfo{
        uint256 apk0;
        uint256 apk1;
        uint256 apk2;
        uint256 apk3;
        uint256 sigma0;
        uint256 sigma1;
    }

        

    constructor(){
        delegates = [acct_0, acct_1];
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
        uint256 ethAmount = 1e18;
        uint256 eigenAmount = 1e18;
        // uint96 registrantEthWeightBefore = uint96(
        //     dlReg.weightOfOperatorEth(signers[0])
        // );
        // uint96 registrantEigenWeightBefore = uint96(
        //     dlReg.weightOfOperatorEigen(signers[0])
        // );
        uint96 registrantEthWeightBefore = dlReg.weightOfOperator(signers[0], 0);
        uint96 registrantEigenWeightBefore = dlReg.weightOfOperator(signers[0], 1);
        DelegationTerms _dt = _deployDelegationTerms(signers[0]);
        _testRegisterAsDelegate(signers[0], _dt);
        _testWethDeposit(acct_0, ethAmount);
        _testDepositEigen(acct_0, eigenAmount);
        _testDelegateToOperator(acct_0, signers[0]);

        uint96 registrantEthWeightAfter = dlReg.weightOfOperator(signers[0], 0);
        uint96 registrantEigenWeightAfter = dlReg.weightOfOperator(signers[0], 1);
        emit log_named_uint("registrantEthWeightBefore", registrantEthWeightBefore);
        emit log_named_uint("registrantEthWeightAfter", registrantEthWeightAfter);
        assertTrue(
            registrantEthWeightAfter - registrantEthWeightBefore == ethAmount, 
            "testDelegation: registrantEthWeight did not increment by the right amount"
        );
        assertTrue(
            registrantEigenWeightAfter - registrantEigenWeightBefore == eigenAmount, 
            "Eigen weights did not increment by the right amount"
        );
        IInvestmentStrategy _strat = investmentManager.investorStrats(acct_0, 0);
        assertTrue(address(_strat) != address(0), "investorStrats not updated correctly");
        assertTrue(delegation.operatorShares(signers[0], _strat) > 0, "operatorShares not updated correctly");
    }

    // registers a fixed address as a delegate, delegates to it from a second address, and checks that the delegate's voteWeights increase properly
    function testDelegationMultipleStrategies(uint16 numStratsToAdd) public {
        cheats.assume(numStratsToAdd > 0 && numStratsToAdd <= 20);
        uint96 registrantEthWeightBefore = dlReg.weightOfOperator(signers[0], 0);
        uint96 registrantEigenWeightBefore = dlReg.weightOfOperator(signers[0], 1);
        DelegationTerms _dt = _deployDelegationTerms(signers[0]);

        _testRegisterAsDelegate(signers[0], _dt);
        _testDepositStrategies(signers[1], 1e18, numStratsToAdd);
        _testDepositEigen(signers[1], 1e18);
        _testDelegateToOperator(signers[1], signers[0]);
        uint96 registrantEthWeightAfter = dlReg.weightOfOperator(signers[0], 0);
        uint96 registrantEigenWeightAfter = dlReg.weightOfOperator(signers[0], 1);
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
        _testDepositEigen(acct_0, 1e18);
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


        //G2 coordinates for aggregate PKs for 15 signers
        apks.push(uint256(20820493588973199354272631301248587752629863429201347184003644368113679196121));
        apks.push(uint256(18507428821816114421698399069438744284866101909563082454551586195885282320634));
        apks.push(uint256(1263326262781780932600377484793962587101562728383804037421955407439695092960));
        apks.push(uint256(3512517006108887301063578607317108977425754510174956792003926207778790018672));

        //15 signers' associated sigma
        sigmas.push(uint256(7155561537864411538991615376457474334371827900888029310878886991084477170996));
        sigmas.push(uint256(10352977531892356631551102769773992282745949082157652335724669165983475588346));
             
        address operator = signers[0];
        _testInitiateDelegation(operator, 1e18);
        _payRewards(operator);
    }

    function _testInitiateDelegation(address operator, uint256 amountToDeposit) public {
        //setting up operator's delegation terms
        weth.transfer(operator, 1e18);
        weth.transfer(_challenger, 1e18);
        dt = _deployDelegationTerms(operator);
        _testRegisterAsDelegate(operator, dt);

        for(uint i; i < delegates.length; i++){
            //initialize weth, eigen and eth balances for delegator
            // eigen.safeTransferFrom(address(this), delegates[i], 0, amountEigenToDeposit, "0x");
            eigenToken.transfer(delegates[i], amountEigenToDeposit);
            weth.transfer(delegates[i], amountToDeposit);
            cheats.deal(delegates[i], amountEthToDeposit);

            cheats.startPrank(delegates[i]);

            //depositing delegator's eth into consensus layer
            deposit.depositEthIntoConsensusLayer{value: amountEthToDeposit}("0x", "0x", depositContract.get_deposit_root());

            //deposit delegator's eigen into investment manager
            // eigen.setApprovalForAll(address(investmentManager), true);
            // investmentManager.depositEigen(amountEigenToDeposit);
            eigenToken.approve(address(investmentManager), type(uint256).max);
            investmentManager.depositIntoStrategy(delegates[i], eigenStrat, eigenToken, amountEigenToDeposit);

            //depost weth into investment manager
            weth.approve(address(investmentManager), type(uint256).max);
            investmentManager.depositIntoStrategy(
                delegates[i],
                strat,
                weth,
                amountToDeposit);

            cheats.stopPrank();

            //delegate delegator's deposits to operator
            _testDelegateToOperator(delegates[i], operator);
        }

        cheats.startPrank(operator);
        //register operator with vote weigher so they can get payment
        uint8 registrantType = 3;
        string memory socket = "255.255.255.255";
        // function registerOperator(uint8 registrantType, bytes calldata data, string calldata socket)
        dlReg.registerOperator(registrantType, ephemeralKey, registrationData[0], socket);
        cheats.stopPrank();

    }

    function _payRewards(address operator) internal {
        uint120 amountRewards = 10;
        

        //Operator submits claim to rewards
        _testCommitPayment(operator, amountRewards);
        

        //initiate challenge
        _testInitPaymentChallenge(operator, 5, 3);        

        bool half = true;

        //Challenge payment test
        operatorDisputesChallenger(operator, half, 2, 3);
        // challengerDisputesOperator(operator, half, 1, 1);
        // operatorDisputesChallenger(operator, half, 1, 1);

    }

    function operatorDisputesChallenger(address operator, bool half, uint120 amount1, uint120 amount2) public{

        cheats.startPrank(operator);
        if (dataLayrPaymentManager.getDiff(operator) == 1){
            cheats.stopPrank();
            return;
        }
        
        dataLayrPaymentManager.challengePaymentHalf(operator, half, amount1, amount2);
        cheats.stopPrank();

        //Now we calculate the challenger's response amounts
    }

    // function _challengerDisputesOperator(address operator, bool half, uint120 amount1, uint120 amount2) internal{
    function challengerDisputesOperator(address challenger, address operator, bool half, uint120 amount1, uint120 amount2) public{
        cheats.startPrank(challenger);
        if (dataLayrPaymentManager.getDiff(operator) == 1){
            cheats.stopPrank();
            return;
        }
        dataLayrPaymentManager.challengePaymentHalf(operator, half, amount1, amount2);
        cheats.stopPrank();

    }

    //initiates the payment challenge from the challenger, with split that the challenger thinks is correct
    function _testInitPaymentChallenge(address operator, uint120 amount1, uint120 amount2) internal {
        cheats.startPrank(_challenger);
        weth.approve(address(dataLayrPaymentManager), type(uint256).max);

        //challenger initiates challenge
        dataLayrPaymentManager.challengePaymentInit(operator, amount1, amount2);
        
        // DataLayrPaymentManager.PaymentChallenge memory _paymentChallengeStruct = dataLayrPaymentManager.operatorToPaymentChallenge(operator);
        cheats.stopPrank();
    }





     //Operator submits claim or commit for a payment amount
    function _testCommitPayment(address operator, uint120 _amountRewards) internal {
        uint32 numberOfSigners = 15;
        _testRegisterSigners(numberOfSigners, false);

        uint32 blockNumber;

    // scoped block helps fix 'stack too deep' errors
    {
        IDataLayrServiceManager.DataStoreSearchData memory searchData  = _testInitDataStore();
        uint32 numberOfNonSigners = 0;

        blockNumber = uint32(block.number);
        uint32 dataStoreId = dlsm.dataStoreId()-1;

        _testCommitDataStore(searchData.metadata.headerHash,  numberOfNonSigners,apks, sigmas, blockNumber, dataStoreId, searchData);
        // bytes32 sighash = dlsm.getDataStoreIdSignatureHash(dlsm.dataStoreId() - 1);
        // assertTrue(sighash != bytes32(0), "Data store not committed");
    }
        cheats.stopPrank();

        // // try initing another dataStore, so currentDataStoreId > fromDataStoreId
        // _testInitDataStore();
        bytes memory header = hex"0102030405060708091011121314151617181921";
        uint32 totalBytes = 1e6;
        // uint32 storePeriodLength = 600;

        //weth is set as the paymentToken of dlsm, so we must approve dlsm to transfer weth
        weth.transfer(storer, 1e11);
        cheats.startPrank(storer);
        weth.approve(address(dataLayrPaymentManager), type(uint256).max);
        dataLayrPaymentManager.depositFutureFees(storer, 1e11);
        blockNumber = 1;
        //todo: duration
        dlsm.initDataStore(storer, header, 2, totalBytes, blockNumber);
        cheats.stopPrank();


        cheats.startPrank(operator);
        weth.approve(address(dataLayrPaymentManager), type(uint256).max);

        // uint256 fromDataStoreId = IBLSRegistryWithBomb(address(dlsm.repository().voteWeigher())).getFromDataStoreIdForOperator(operator);
        uint32 newCurrentDataStoreId = dlsm.dataStoreId() - 1;
        dataLayrPaymentManager.commitPayment(newCurrentDataStoreId, _amountRewards);
        cheats.stopPrank();
        //assertTrue(weth.balanceOf(address(dt)) == currBalance + amountRewards, "rewards not transferred to delegation terms contract");
    
    }
    //commits data store to data layer
    function _testCommitDataStore(
            bytes32 headerHash, 
            uint32 numberOfNonSigners, 
            uint256[] memory apk, 
            uint256[] memory sigma,
            uint32 blockNumber,
            uint32 dataStoreId,
            IDataLayrServiceManager.DataStoreSearchData memory searchData
            ) internal{

        /** 
        @param data This calldata is of the format:
                <
                bytes32 headerHash,
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
            headerHash,
            uint48(dlReg.getLengthOfTotalStakeHistory() - 1),
            blockNumber,
            dataStoreId,
            numberOfNonSigners,
            // no pubkeys here since zero nonSigners for now
            uint32(dlReg.getApkUpdatesLength() - 1),
            apk[0],
            apk[1],
            apk[2],
            apk[3],
            sigma[0],
            sigma[1]
        );


        dlsm.confirmDataStore(data, searchData);

    }

    /**
    @param numberOfSigners is the number of signers in the quorum of DLNs
    @param includeOperator is a boolean that indicates whether or not we want to also register 
    the operator no. 0, for test case where they are not already registered as a delegator.
    **/
    function _testRegisterSigners(uint32 numberOfSigners, bool includeOperator) internal{
        uint256 start = 1;
        if (includeOperator){
            start = 0;
        }

        //register all the operators
        //skip i = 0 since we have already registered signers[0] !!
        for (uint256 i = start; i < numberOfSigners; ++i) {
            // emit log_named_uint("i", i);
            _testRegisterAdditionalSelfOperator(
                signers[i],
                registrationData[i]
            );
        }

    }

//testing inclusion of nonsigners in DLN quorum, ensuring that nonsigner inclusion proof is working correctly.
    function testForNonSigners() public {
        address operator = signers[0];
        _testInitiateDelegation(operator, 1e18);

        nonSignerInfo memory nonsigner;
        signerInfo memory signer;

        nonsigner.xA0 = (uint256(10245738255635135293623161230197183222740738674756428343303263476182774511624));
        nonsigner.xA1 = (uint256(10281853605827367652226404263211738087634374304916354347419537904612128636245));
        nonsigner.yA0 = (uint256(3091447672609454381783218377241231503703729871039021245809464784750860882084));
        nonsigner.yA1 = (uint256(18210007982945446441276599406248966847525243540006051743069767984995839204266));


        signer.apk0 = uint256(20820493588973199354272631301248587752629863429201347184003644368113679196121);
        signer.apk1 = uint256(18507428821816114421698399069438744284866101909563082454551586195885282320634);
        signer.apk2 = uint256(1263326262781780932600377484793962587101562728383804037421955407439695092960);
        signer.apk3 = uint256(3512517006108887301063578607317108977425754510174956792003926207778790018672);
        signer.sigma0 = uint256(11158738887387636951551175125607721554638045534548101012382762810906820102473);
        signer.sigma1 = uint256(3135580093883685723788059851431412645937134768491818213416377523852295292067 );
        
        uint32 numberOfSigners = 15;
        _testRegisterSigners(numberOfSigners, false);
        
    // scoped block helps fix 'stack too deep' errors
    {
        IDataLayrServiceManager.DataStoreSearchData memory searchData  = _testInitDataStore();
        uint32 numberOfNonSigners = 1;
        uint32 blockNumber = uint32(block.number);
        uint32 dataStoreId = dlsm.dataStoreId()-1;


        bytes memory data = _getCallData(searchData.metadata.headerHash, numberOfNonSigners, signer, nonsigner, blockNumber, dataStoreId);

        
        uint gasbefore = gasleft();
        
        dlsm.confirmDataStore(data, searchData);

        emit log_named_uint("gas cost", gasbefore - gasleft());



        // bytes32 sighash = dlsm.getDataStoreIdSignatureHash(dlsm.dataStoreId() - 1);
        // assertTrue(sighash != bytes32(0), "Data store not committed");
    }


    }

    //Internal function for assembling calldata - prevents stack too deep errors
    function _getCallData(
            bytes32 headerHash, 
            uint32 numberOfNonSigners, 
            signerInfo memory signers,
            nonSignerInfo memory nonsigners,
            uint32 blockNumber,
            uint32 dataStoreId
    ) internal view returns(bytes memory){

        /** 
        @param data This calldata is of the format:
            <
             bytes32 headerHash,
             uint48 index of the totalStake corresponding to the dataStoreId in the 'totalStakeHistory' array of the BLSRegistryWithBomb
             uint32 blockNumber
             uint32 dataStoreId
             uint32 numberOfNonSigners,
             uint256[numberOfSigners][4] pubkeys of nonsigners,
             uint32 apkIndex,
             uint256[4] apk,
             uint256[2] sigma
            >s
        */
        bytes memory data = abi.encodePacked(
            headerHash,
            uint48(dlReg.getLengthOfTotalStakeHistory() - 1),
            blockNumber,
            dataStoreId,
            numberOfNonSigners,
            nonsigners.xA0,
            nonsigners.xA1,
            nonsigners.yA0,
            nonsigners.yA1
        );

         data = abi.encodePacked(
            data,
            uint32(0),
            uint32(dlReg.getApkUpdatesLength() - 1),
            signers.apk0,
            signers.apk1,
            signers.apk2,
            signers.apk3,
            signers.sigma0,
            signers.sigma1
        );

        return data;

    }


}