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
    address[2] public delegates;
    uint256[] apks;
    uint256[] sigmas;

    //uint256 amountEigenToDeposit = 1e17;
    //uint256 amountEthToDeposit = 2e19;
    address _challenger = address(0x6966904396bF2f8b173350bCcec5007A52669873);
    mapping(IInvestmentStrategy => uint256) public initialOperatorShares;

    struct nonSignerInfo {
        uint256 xA0;
        uint256 xA1;
        uint256 yA0;
        uint256 yA1;
    }

    struct signerInfo {
        uint256 apk0;
        uint256 apk1;
        uint256 apk2;
        uint256 apk3;
        uint256 sigma0;
        uint256 sigma1;
    }


    constructor() {
        delegates = [acct_0, acct_1];
    }


    /// @notice testing if an operator can register to themselves.
    function testSelfOperatorRegister() public {
        _testRegisterAdditionalSelfOperator(signers[0], registrationData[0]);
    }

    /// @notice testing if an operator can delegate to themselves.
    /// @param sender is the address of the operator.
    function testSelfOperatorDelegate(address sender) public {
        cheats.assume(sender != address(0));
        cheats.assume(sender != address(eigenLayrProxyAdmin));
        _testRegisterAsDelegate(sender, IDelegationTerms(sender));
    }

    
    function testTwoSelfOperatorsRegister() public {
        _testRegisterAdditionalSelfOperator(signers[0], registrationData[0]);
        _testRegisterAdditionalSelfOperator(signers[1], registrationData[1]);
    }

    /// @notice registers a fixed address as a delegate, delegates to it from a second address, 
    ///         and checks that the delegate's voteWeights increase properly
    /// @param operator is the operator being delegated to.
    /// @param staker is the staker delegating stake to the operator.
    function testDelegation(
        address operator, 
        address staker, 
        uint256 ethAmount, 
        uint256 eigenAmount
        ) public fuzzedAddress(operator) fuzzedAddress(staker) { 

        cheats.assume(staker != operator);
        cheats.assume(ethAmount >=0 && ethAmount <= 1e18); 
        cheats.assume(eigenAmount >=0 && eigenAmount <= 1e18); 

        if(!delegation.isDelegate(operator)){
            _testRegisterAsDelegate(operator, IDelegationTerms(operator));
        }

        uint256 operatorEthWeightBefore = dlReg.weightOfOperator(operator, 0);
        uint256 operatorEigenWeightBefore = dlReg.weightOfOperator(operator, 1);

        //making additional deposits to the investment strategies
        assertTrue(delegation.isNotDelegated(staker)==true, "testDelegation: staker is not delegate");
        _testWethDeposit(staker, ethAmount);
        _testDepositEigen(staker, eigenAmount);
        _testDelegateToOperator(staker, operator);
        assertTrue(delegation.isDelegated(staker)==true, "testDelegation: staker is not delegate");

        (
            IInvestmentStrategy[] memory updatedStrategies,
            uint256[] memory updatedShares
        ) = investmentManager.getDeposits(staker);

        {
            uint256 stakerEthWeight = investmentManager.investorStratShares(staker, updatedStrategies[0]);
            uint256 stakerEigenWeight = investmentManager.investorStratShares(staker, updatedStrategies[1]);

        
            uint256 operatorEthWeightAfter = dlReg.weightOfOperator(operator, 0);
            uint256 operatorEigenWeightAfter = dlReg.weightOfOperator(operator, 1);
        

            assertTrue(
                operatorEthWeightAfter - operatorEthWeightBefore == stakerEthWeight,
                "testDelegation: operatorEthWeight did not increment by the right amount"
            );
            assertTrue(
                operatorEigenWeightAfter - operatorEigenWeightBefore ==
                    stakerEigenWeight,
                "Eigen weights did not increment by the right amount"
            );

        }
        {
            IInvestmentStrategy _strat = investmentManager.investorStrats(
                staker,
                0
            );
            assertTrue(
                address(_strat) != address(0),
                "investorStrats not updated correctly"
            );

            assertTrue(
                delegation.operatorShares(operator, _strat) - updatedShares[0] == 0,
                "ETH operatorShares not updated correctly"
            );
        }
    }

    /// @notice test staker's ability ot undelegate from an operator.
    /// @param operator is the operator being delegated to.
    /// @param staker is the staker delegating stake to the operator.
    function testUndelegation(
            address operator, 
            address staker, 
            uint256 ethAmount,
            uint256 eigenAmount
        ) public fuzzedAddress(operator) fuzzedAddress(staker) {

        cheats.assume(staker != operator);
        cheats.assume(ethAmount >=0 && ethAmount <= 1e18); 
        cheats.assume(eigenAmount >=0 && eigenAmount <= 1e18); 


        testDelegation(operator, staker, ethAmount, eigenAmount);


        //delegator-specific information
        (
            IInvestmentStrategy[] memory delegatorStrategies,
            uint256[] memory delegatorShares
        ) = investmentManager.getDeposits(staker);


        for (uint256 k = 0; k < delegatorStrategies.length; k++) {
            initialOperatorShares[delegatorStrategies[k]] = delegation
                .operatorShares(operator, delegatorStrategies[k]);
        }

        _testCommitUndelegation(staker);
        cheats.warp(block.timestamp + delegation.undelegationFraudProofInterval()+1);

        _testFinalizeUndelegation(staker);

        

        for (uint256 k = 0; k < delegatorStrategies.length; k++) {
            uint256 operatorSharesBefore = initialOperatorShares[
                delegatorStrategies[k]
            ];
            uint256 operatorSharesAfter = delegation.operatorShares(
                operator,
                delegatorStrategies[k]
            );

            assertTrue(
                delegatorShares[k] == operatorSharesBefore - operatorSharesAfter, "testUndelegation: delegator shares not deducted correctly"
            );
        }
        
    }

    
    /// @notice registers a fixed address as a delegate, delegates to it from a second address, 
    ///         and checks that the delegate's voteWeights increase properly
    /// @param operator is the operator being delegated to.
    /// @param staker is the staker delegating stake to the operator.
    function testDelegationMultipleStrategies(
            uint16 numStratsToAdd, 
            address operator,
            address staker
     ) public fuzzedAddress(operator) fuzzedAddress(staker) {

        cheats.assume(staker != operator);

        cheats.assume(numStratsToAdd > 0 && numStratsToAdd <= 20);
        uint96 operatorEthWeightBefore = dlReg.weightOfOperator(
            operator,
            0
        );
        uint96 operatorEigenWeightBefore = dlReg.weightOfOperator(
            operator,
            1
        );
        _testRegisterAsDelegate(operator, IDelegationTerms(operator));
        _testDepositStrategies(staker, 1e18, numStratsToAdd);
        _testDepositEigen(staker, 1e18);
        _testDelegateToOperator(staker, operator);
        uint96 operatorEthWeightAfter = dlReg.weightOfOperator(operator, 0);
        uint96 operatorEigenWeightAfter = dlReg.weightOfOperator(operator,1);
        assertTrue(
            operatorEthWeightAfter > operatorEthWeightBefore,
            "testDelegation: operatorEthWeight did not increase!"
        );
        assertTrue(
            operatorEigenWeightAfter > operatorEigenWeightBefore,
            "testDelegation: operatorEthWeight did not increase!"
        );
    }

    /// @notice test to see if an operator who is slashed/frozen 
    ///         cannot be undelegated from by their stakers.
    /// @param operator is the operator being delegated to.
    /// @param staker is the staker delegating stake to the operator.
    function testSlashedOperatorUndelegation(
            address operator, 
            address staker, 
            uint256 ethAmount, 
            uint256 eigenAmount
         ) public fuzzedAddress(operator) fuzzedAddress(staker){
        cheats.assume(staker != operator);
        testDelegation(operator, staker, ethAmount, eigenAmount);

        address slashingContract = slasher.owner();

        address[] memory slashingContracts = new address[](1);
        slashingContracts[0] = slashingContract;

        cheats.startPrank(slashingContract);
        slasher.addPermissionedContracts(slashingContracts);
        slasher.freezeOperator(operator);
        cheats.stopPrank();

        //initiating undelegation
        cheats.startPrank(staker);
        cheats.expectRevert(bytes("EigenLayrDelegation.initUndelegation: operator has been frozen. must wait for resolution before undelegation"));
        delegation.initUndelegation();
    }

    /// @notice This function tests to ensure that a delegation contract
    ///         cannot be intitialized multiple times
    function testCannotInitMultipleTimesDelegation() cannotReinit public {
        //delegation has already been initialized in the Deployer test contract
        delegation.initialize(
            investmentManager,
            undelegationFraudProofInterval
        );
    }


    /// @notice This function tests to ensure that a you can't register as a delegate multiple times
    /// @param operator is the operator being delegated to.
    function testRegisterAsDelegateMultipleTimes(
            address operator
        ) public fuzzedAddress(operator){
        _testRegisterAsDelegate(operator, IDelegationTerms(operator));
        cheats.expectRevert(bytes("EigenLayrDelegation.registerAsDelegate: Delegate has already registered"));
        _testRegisterAsDelegate(operator, IDelegationTerms(operator));  
    }

    /// @notice This function tests to ensure that a staker cannot delegate to an unregistered operator
    /// @param delegate is the unregistered operator
    function testDelegationToUnregisteredDelegate(
        address delegate
        ) public fuzzedAddress(delegate){
        //deposit into 1 strategy for signers[1], who is delegating to the unregistered operator
        _testDepositStrategies(signers[1], 1e18, 1);
        _testDepositEigen(signers[1], 1e18);

        cheats.expectRevert(bytes("EigenLayrDelegation._delegate: operator has not registered as a delegate yet. Please call registerAsDelegate(IDelegationTerms dt) first"));
        cheats.startPrank(signers[1]);
        delegation.delegateTo(delegate);
        cheats.stopPrank();
    }


    /// @notice This function tests to ensure that a delegator can re-delegate to an operator after undelegating.
    /// @param operator is the operator being delegated to.
    /// @param staker is the staker delegating stake to the operator.
    function testRedelegateAfterUndelegation(
            address operator, 
            address staker, 
            uint256 ethAmount, 
            uint256 eigenAmount
        ) public fuzzedAddress(operator) fuzzedAddress(staker){
        cheats.assume(staker != operator);

        //this function performs delegation and undelegation
        testUndelegation(operator, staker, ethAmount, eigenAmount);

        (IInvestmentStrategy[] memory strategies,) = investmentManager.getDeposits(staker);

        //warps past fraudproof time interval
        cheats.warp(block.timestamp + undelegationFraudProofInterval + 1);
        testDelegation(operator, staker, ethAmount, eigenAmount);
    }

    //testing inclusion of nonsigners in DLN quorum, ensuring that nonsigner inclusion proof is working correctly.
    function testForNonSigners(
        uint256 ethAmount, 
        uint256 eigenAmount
    ) public {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e10);
        
        address operator = signers[0];
        _testInitiateDelegation(operator, eigenAmount, ethAmount);
        nonSignerInfo memory nonsigner;
        signerInfo memory signer;

        nonsigner.xA0 = (
            uint256(
                10245738255635135293623161230197183222740738674756428343303263476182774511624
            )
        );
        nonsigner.xA1 = (
            uint256(
                10281853605827367652226404263211738087634374304916354347419537904612128636245
            )
        );
        nonsigner.yA0 = (
            uint256(
                3091447672609454381783218377241231503703729871039021245809464784750860882084
            )
        );
        nonsigner.yA1 = (
            uint256(
                18210007982945446441276599406248966847525243540006051743069767984995839204266
            )
        );

        signer.apk0 = uint256(
            20820493588973199354272631301248587752629863429201347184003644368113679196121
        );
        signer.apk1 = uint256(
            18507428821816114421698399069438744284866101909563082454551586195885282320634
        );
        signer.apk2 = uint256(
            1263326262781780932600377484793962587101562728383804037421955407439695092960
        );
        signer.apk3 = uint256(
            3512517006108887301063578607317108977425754510174956792003926207778790018672
        );
        signer.sigma0 = uint256(
            7232102842299801988888616268506476902050501317623869691846247376690344395462
        );
        signer.sigma1 = uint256(
            14957250584972173579780704932503635695261143933757715744951524340217507753217
        );

        uint32 numberOfSigners = 15;
        _testRegisterSigners(numberOfSigners, false);

        

        // scoped block helps fix 'stack too deep' errors
        {
            uint256 initTime = 1000000001;
            IDataLayrServiceManager.DataStoreSearchData
                memory searchData = _testInitDataStore(initTime, address(this));
            uint32 numberOfNonSigners = 1;
            uint32 dataStoreId = dlsm.taskNumber() - 1;

            bytes memory data = _getCallData(
                keccak256(abi.encodePacked(searchData.metadata.globalDataStoreId, searchData.metadata.headerHash, searchData.duration, initTime, uint32(0))),
                numberOfNonSigners,
                signer,
                nonsigner,
                searchData.metadata.blockNumber,
                dataStoreId
            );

            uint gasbefore = gasleft();

            dlsm.confirmDataStore(data, searchData);

            emit log_named_uint("gas cost", gasbefore - gasleft());

            // bytes32 sighash = dlsm.getDataStoreIdSignatureHash(dlsm.taskNumber() - 1);
            // assertTrue(sighash != bytes32(0), "Data store not committed");
        }
    }

    /// @notice testing permissions setInvestmentManager and 
    ///         setUndelegationFraudProofInterval functions.

    function testOwnableFunctions(address badGuy, uint256 altFraudProofInterval) fuzzedAddress(badGuy) public {
        cheats.startPrank(badGuy);
        EigenLayrDelegation altDelegation = new EigenLayrDelegation();
        IInvestmentManager altInvestmentManager = new InvestmentManager(altDelegation);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        delegation.setInvestmentManager(altInvestmentManager);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        delegation.setUndelegationFraudProofInterval(altFraudProofInterval);
        cheats.stopPrank();
    }

    

    //*******INTERNAL FUNCTIONS*********//
    
    function _testInitiateDelegation(address operator, uint256 amountEigenToDeposit, uint256 amountEthToDeposit)
        public
    {
        //setting up operator's delegation terms
        weth.transfer(operator, 1e18);
        weth.transfer(_challenger, 1e18);
        _testRegisterAsDelegate(operator, IDelegationTerms(operator));

        for (uint i; i < delegates.length; i++) {
            //initialize weth, eigen and eth balances for delegator
            eigenToken.transfer(delegates[i], amountEigenToDeposit);
            weth.transfer(delegates[i], amountEthToDeposit);
            cheats.deal(delegates[i], amountEthToDeposit);

            cheats.startPrank(delegates[i]);

            //deposit delegator's eigen into investment manager
            eigenToken.approve(address(investmentManager), type(uint256).max);

            investmentManager.depositIntoStrategy(
                delegates[i],
                eigenStrat,
                eigenToken,
                amountEigenToDeposit
            );

            //depost weth into investment manager
            weth.approve(address(investmentManager), type(uint256).max);
            investmentManager.depositIntoStrategy(
                delegates[i],
                wethStrat,
                weth,
                amountEthToDeposit
            );

            cheats.stopPrank();

            uint256 operatorEigenSharesBefore = delegation.operatorShares(operator, eigenStrat);
            uint256 operatorWETHSharesBefore = delegation.operatorShares(operator, wethStrat);

            //delegate delegator's deposits to operator
            _testDelegateToOperator(delegates[i], operator);
            //testing to see if increaseOperatorShares worked
            assertTrue(delegation.operatorShares(operator, eigenStrat) - operatorEigenSharesBefore == amountEigenToDeposit);
            assertTrue(delegation.operatorShares(operator, wethStrat) - operatorWETHSharesBefore == amountEthToDeposit);

        }

        cheats.startPrank(operator);
        //register operator with vote weigher so they can get payment
        uint8 registrantType = 3;
        string memory socket = "255.255.255.255";
        // function registerOperator(
        //     uint8 registrantType,
        //     bytes32 ephemeralKeyHash,
        //     bytes calldata data,
        //     string calldata socket
        // )
        dlReg.registerOperator(
            registrantType,
            ephemeralKey,
            registrationData[0],
            socket
        );
        cheats.stopPrank();
    }



    //commits data store to data layer
    function _testCommitDataStore(
        bytes32 msgHash,
        uint32 numberOfNonSigners,
        uint256[] memory apk,
        uint256[] memory sigma,
        uint32 blockNumber,
        uint32 dataStoreId,
        IDataLayrServiceManager.DataStoreSearchData memory searchData
    ) internal {
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
            msgHash,
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
    function _testRegisterSigners(uint32 numberOfSigners, bool includeOperator)
        internal
    {
        uint256 start = 1;
        if (includeOperator) {
            start = 0;
        }
        

        //register all the operators
        //skip i = 0 since we have already registered signers[0] !!
        for (uint256 i = start; i < numberOfSigners; ++i) {
            
            _testRegisterAdditionalSelfOperator(
                signers[i],
                registrationData[i]
            );
        }
    }

    function _testCommitUndelegation(address sender) internal {
        cheats.startPrank(sender);
        delegation.initUndelegation();
        delegation.commitUndelegation();
        assertTrue(delegation.undelegationFinalizedTime(sender)==block.timestamp + undelegationFraudProofInterval, "_testCommitUndelegation: undelegation time not set correctly");
        cheats.stopPrank();
    }

    function _testFinalizeUndelegation(address sender) internal {
        cheats.startPrank(sender);
        delegation.finalizeUndelegation();
        cheats.stopPrank();
        assertTrue(delegation.isNotDelegated(sender)==true, "testDelegation: staker is not undelegated");
    }

    //Internal function for assembling calldata - prevents stack too deep errors
    function _getCallData(
        bytes32 msgHash,
        uint32 numberOfNonSigners,
        signerInfo memory signers,
        nonSignerInfo memory nonsigners,
        uint32 blockNumber,
        uint32 dataStoreId
    ) internal view returns (bytes memory) {
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
            >s
        */
        bytes memory data = abi.encodePacked(
            msgHash,
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
