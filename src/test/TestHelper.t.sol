// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../test/Deployer.t.sol";


contract TestHelper is EigenLayrDeployer {


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