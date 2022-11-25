// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../contracts/libraries/BytesLib.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "../test/DataLayrTestHelper.t.sol";

contract PaymentsTests is DataLayrTestHelper {
    using BytesLib for bytes;
    using Math for uint256;

    IERC20 paymentToken;

    uint256[2] apkG1;
    uint256[4] apkG2;
    uint256[2] sigma;

    ///@notice this function tests depositing fees on behalf of a rollupContract to an operator
    ///@param user is the user of the middleware who is paying fees to the operator
    ///            (a rollup contract in the case of DL, for example)
    ///@param amountToDeposit is the amount of future fees deposited by the @param user

    function testDepositFutureFees(address user, uint96 amountToDeposit) public fuzzedAddress(user) {
        cheats.assume(user != address(dataLayrPaymentManager));
        paymentToken = dataLayrPaymentManager.paymentToken();

        cheats.assume(amountToDeposit < paymentToken.balanceOf(address(this)));
        cheats.assume(amountToDeposit > 0);
        require(
            paymentToken.balanceOf(address(this)) != 0,
            "testDepositFutureFees: we aren't testing anything if this is failing"
        );

        paymentToken.transfer(user, amountToDeposit);

        uint256 paymentManagerTokenBalanceBefore = paymentToken.balanceOf(address(dataLayrPaymentManager));
        uint256 operatorFeeBalanceBefore = dataLayrPaymentManager.depositsOf(user);

        cheats.startPrank(user);
        paymentToken.approve(address(dataLayrPaymentManager), type(uint256).max);
        dataLayrPaymentManager.depositFutureFees(user, amountToDeposit);
        cheats.stopPrank();

        uint256 paymentManagerTokenBalanceAfter = paymentToken.balanceOf(address(dataLayrPaymentManager));
        uint256 operatorFeeBalanceAfter = dataLayrPaymentManager.depositsOf(user);

        assertTrue(
            paymentManagerTokenBalanceAfter - paymentManagerTokenBalanceBefore == amountToDeposit,
            "testDepositFutureFees: deposit not reflected in paymentManager contract balance"
        );
        assertTrue(
            operatorFeeBalanceAfter - operatorFeeBalanceBefore == amountToDeposit,
            "testDepositFutureFees: operator deposit balance not updated correctly"
        );
    }

    ///@notice this function tests paying fees without delegation of payment rights to a third party
    ///@param user is the user of the middleware who is paying fees to the operator
    ///            (a rollup contract in the case of DL, for example)
    ///@param amountToDeposit is the amount of future fees deposited by the @param user
    function testPayFee(address user, uint96 amountToDeposit) public fuzzedAddress(user) {
        testDepositFutureFees(user, amountToDeposit);
        uint256 operatorFeeBalanceBefore = dataLayrPaymentManager.depositsOf(user);

        cheats.startPrank(address(dlsm));
        dataLayrPaymentManager.payFee(user, user, amountToDeposit);
        cheats.stopPrank();

        uint256 operatorFeeBalanceAfter = dataLayrPaymentManager.depositsOf(user);
        assertTrue(
            operatorFeeBalanceBefore - operatorFeeBalanceAfter == amountToDeposit,
            "testDepositFutureFees: operator deposit balance not updated correctly"
        );
    }

    ///@notice tests setting payment collateral from the valid address
    ///@param fraudProofCollateral is the new value for the amount of fraudproof collateral being put up in the case of payment claims
    function testSetPaymentCollateral(uint256 fraudProofCollateral) public {
        address serviceManagerOwner = dlsm.owner();
        cheats.startPrank(serviceManagerOwner);
        dataLayrPaymentManager.setPaymentFraudproofCollateral(fraudProofCollateral);
        assertTrue(
            dataLayrPaymentManager.paymentFraudproofCollateral() == fraudProofCollateral,
            "testSetPaymentCollateral: paymentFraudproofCollateral is not set correctly"
        );
        cheats.stopPrank();
    }

    ///@notice tests setting payment collateral from an unauthorized address
    ///@param fraudProofCollateral is the amount of payment fraudproof collateral being put up byt the repository owner
    ///@param unauthorizedDLSMOwner is the unauthorized address
    function testUnauthorizedSetPaymentCollateral(uint256 fraudProofCollateral, address unauthorizedDLSMOwner)
        public
        fuzzedAddress(unauthorizedDLSMOwner)
    {
        cheats.assume(unauthorizedDLSMOwner != dlsm.owner());
        cheats.startPrank(unauthorizedDLSMOwner);
        cheats.expectRevert(bytes("onlyServiceManagerOwner"));
        dataLayrPaymentManager.setPaymentFraudproofCollateral(fraudProofCollateral);
        cheats.stopPrank();
    }

    ///@notice tests commiting to reward payouts
    ///@param ethAmount is the amount of delegated eth
    ///@param eigenAmount is the amount of eigen
    function testRewardPayouts(uint8 index, uint256 ethAmount, uint256 eigenAmount) public fuzzedOperatorIndex(index) {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);
        {
            (apkG1[0], apkG1[1]) = getAggregatePublicKeyG1();
            (apkG2[0], apkG2[1], apkG2[2], apkG2[3]) = getAggregatePublicKeyG2();
        }
        (sigma[0], sigma[1]) = getAggSignature(); //(signatureData[index*2], signatureData[2*index + 1]);

        //hardcoding values
        address operator = getOperatorAddress(0);
        uint32 numberOfSigners = 15;
        uint96 amountRewards = 10;

        uint8 operatorType = 3;
        _testInitiateDelegation(0, eigenAmount, ethAmount);

        _testRegisterBLSPubKey(0);
        _testRegisterOperatorWithDataLayr(0, operatorType, testEphemeralKey, testSocket);

        _testRegisterSigners(numberOfSigners, false);
        _testInitandConfirmDataStore();
        _incrementDataStoreID();
        _testCommitPayment(operator, amountRewards);
    }

    //*******************************
    //
    // Internal functions
    //
    //*******************************

    ///@notice Operator submits claim or commit for a payment amount
    ///@param operator is the operator address
    ///@param _amountRewards is the amount of rewards to be paid out
    function _testCommitPayment(address operator, uint96 _amountRewards) internal {
        cheats.startPrank(operator);
        weth.approve(address(dataLayrPaymentManager), type(uint256).max);

        uint32 newCurrentDataStoreId = dlsm.taskNumber() - 1;
        dataLayrPaymentManager.commitPayment(newCurrentDataStoreId, _amountRewards);

        cheats.stopPrank();
    }

    ///@notice Operator submits claim or commit for a payment amount
    ///@param operator is the operator address
    function _testRedeemPayment(address operator) internal {
        cheats.startPrank(operator);
        dataLayrPaymentManager.redeemPayment();
        cheats.stopPrank();
    }

    ///@notice simulating init and commit for a datastore
    function _testInitandConfirmDataStore() internal {
        uint32 blockNumber;
        // scoped block helps fix 'stack too deep' errors
        {
            uint256 initTime = 1000000001;
            IDataLayrServiceManager.DataStoreSearchData memory searchData = _testInitDataStore(initTime, address(this), header);
            uint32 numberOfNonSigners = 0;

            blockNumber = uint32(block.number);
            uint32 dataStoreId = dlsm.taskNumber() - 1;
            bytes memory data = abi.encodePacked(
            keccak256(
                abi.encodePacked(
                    searchData.metadata.globalDataStoreId,
                    searchData.metadata.headerHash,
                    searchData.duration,
                    initTime,
                    searchData.index
                )
            ),
            uint48(dlReg.getLengthOfTotalStakeHistory() - 1),
            searchData.metadata.referenceBlockNumber,
            searchData.metadata.globalDataStoreId,
            numberOfNonSigners,
            // no pubkeys here since zero nonSigners for now
            uint32(dlReg.getApkUpdatesLength() - 1),
            apkG1[0],
            apkG1[1],
            apkG2[0],
            apkG2[1],
            apkG2[2],
            apkG2[3],
            sigma[0],
            sigma[1]
        );

        dlsm.confirmDataStore(data, searchData);
        }
        cheats.stopPrank();

        //weth is set as the paymentToken of dlsm, so we must approve dlsm to transfer weth
        weth.transfer(storer, 1e11);
        cheats.startPrank(storer);
        weth.approve(address(dataLayrPaymentManager), type(uint256).max);
        dataLayrPaymentManager.depositFutureFees(storer, 1e11);
        blockNumber = 1;
        cheats.stopPrank();
    }

    ///@notice initiates the payment challenge from the challenger, with split that the challenger thinks is correct
    ///@param operator is the operator address
    ///@param amount1 is the first half of the amount split
    ///@param amount2 is the second half of the amount split
    function _testInitPaymentChallenge(address operator, uint96 amount1, uint96 amount2) internal {
        cheats.startPrank(_challenger);
        weth.approve(address(dataLayrPaymentManager), type(uint256).max);

        //challenger initiates challenge
        dataLayrPaymentManager.initPaymentChallenge(operator, amount1, amount2);

        // DataLayrPaymentManager.PaymentChallenge memory _paymentChallengeStruct = dataLayrPaymentManager.operatorToPaymentChallenge(operator);
        cheats.stopPrank();
    }

    ///@notice increment the datastoreID by init-ing another datastore
    function _incrementDataStoreID() internal {
        uint32 blockNumber = uint32(block.number);
        uint8 duration = 2;
        uint32 totalOperatorsIndex = uint32(dlReg.getLengthOfTotalOperatorsHistory() - 1);
        cheats.startPrank(storer);
        //increments fromDataStoreID so that you can commit a payment
        dlsm.initDataStore(storer, address(this), duration, blockNumber, totalOperatorsIndex, header);
        cheats.stopPrank();
    }
}
