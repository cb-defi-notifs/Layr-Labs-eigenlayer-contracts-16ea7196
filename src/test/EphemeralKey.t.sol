// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../test/DataLayrTestHelper.t.sol";

import "../contracts/libraries/BytesLib.sol";

import "./mocks/EigenDARegistryMock.sol";
import "./mocks/ServiceManagerMock.sol";
import "./Delegation.t.sol";

contract EphemeralKeyTests is DelegationTests {

    EigenDARegistryMock public eigenDAReg;
    ServiceManagerMock public EigenDASM;
     bytes32 public testEphemeralKey1 = 0x3290567812345678123456781234577812345698123456781234567812344389;
    bytes32 public testEphemeralKeyHash1 = keccak256(abi.encode(testEphemeralKey1));
     bytes32 public testEphemeralKey2 = 0x9890567812345678123456780094577812345698123456781234563849087560;
    bytes32 public testEphemeralKeyHash2 = keccak256(abi.encode(testEphemeralKey2));

    function initializeMiddlewares() public {
        EigenDASM = new ServiceManagerMock();

        eigenDAReg = new EigenDARegistryMock(
             EigenDASM,
             investmentManager,
             ephemeralKeyRegistry
        );
    }

    //This function helps with stack too deep issues with "testWithdrawal" test
    function testWithdrawalWrapper(
            address operator, 
            address depositor,
            address withdrawer, 
            uint256 ethAmount,
            uint256 eigenAmount
        ) 
            public 
            fuzzedAddress(operator) 
            fuzzedAddress(depositor) 
            fuzzedAddress(withdrawer) 
        {
            cheats.assume(depositor != operator);
            cheats.assume(ethAmount <= 1e18); 
            cheats.assume(eigenAmount <= 1e18); 
            cheats.assume(ethAmount > 0); 
            cheats.assume(eigenAmount > 0); 

            initializeMiddlewares();

            _testWithdrawalAndDeregistration(operator, depositor, withdrawer, ethAmount, eigenAmount);
        }

    /// @notice test staker's ability to undelegate/withdraw from an operator.
    /// @param operator is the operator being delegated to.
    /// @param depositor is the staker delegating stake to the operator.
    function _testWithdrawalAndDeregistration(
            address operator, 
            address depositor,
            address withdrawer, 
            uint256 ethAmount,
            uint256 eigenAmount
        ) 
            internal 
        {

        testDelegation(operator, depositor, ethAmount, eigenAmount);

        cheats.startPrank(operator);
        investmentManager.slasher().optIntoSlashing(address(EigenDASM));
        cheats.stopPrank();

        eigenDAReg.registerOperator(operator, uint32(block.timestamp) + 3 days, testEphemeralKeyHash1, testEphemeralKeyHash2);

        address delegatedTo = delegation.delegatedTo(depositor);

        // packed data structure to deal with stack-too-deep issues
        DataForTestWithdrawal memory dataForTestWithdrawal;

        // scoped block to deal with stack-too-deep issues
        {
            //delegator-specific information
            (IInvestmentStrategy[] memory delegatorStrategies, uint256[] memory delegatorShares) =
                investmentManager.getDeposits(depositor);
            dataForTestWithdrawal.delegatorStrategies = delegatorStrategies;
            dataForTestWithdrawal.delegatorShares = delegatorShares;

            IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce = 
                IInvestmentManager.WithdrawerAndNonce({
                    withdrawer: withdrawer,
                    // harcoded nonce value
                    nonce: 0
                }
            );
            dataForTestWithdrawal.withdrawerAndNonce = withdrawerAndNonce;
        }

        uint256[] memory strategyIndexes = new uint256[](2);
        IERC20[] memory tokensArray = new IERC20[](2);
        {
            // hardcoded values
            strategyIndexes[0] = 0;
            strategyIndexes[1] = 0;
            tokensArray[0] = weth;
            tokensArray[1] = eigenToken;
        }

        cheats.warp(uint32(block.timestamp) + 1 days);
        cheats.roll(uint32(block.timestamp) + 1 days);

        _testQueueWithdrawal(
            depositor,
            dataForTestWithdrawal.delegatorStrategies,
            tokensArray,
            dataForTestWithdrawal.delegatorShares,
            strategyIndexes,
            dataForTestWithdrawal.withdrawerAndNonce
        );
        uint32 queuedWithdrawalBlock = uint32(block.number);
        
        //now withdrawal block time is before deregistration
        cheats.warp(uint32(block.timestamp) + 2 days);
        cheats.roll(uint32(block.timestamp) + 2 days);
        
        eigenDAReg.deregisterOperator(operator);
        {
            //warp past the serve until time, which is 3 days from the beginning.  THis puts us at 4 days past that point
            cheats.warp(uint32(block.timestamp) + 4 days);
            cheats.roll(uint32(block.timestamp) + 4 days);

            uint256 middlewareTimeIndex =  1;
            _testCompleteQueuedWithdrawalShares(
                depositor,
                dataForTestWithdrawal.delegatorStrategies,
                tokensArray,
                dataForTestWithdrawal.delegatorShares,
                delegatedTo,
                dataForTestWithdrawal.withdrawerAndNonce,
                queuedWithdrawalBlock,
                middlewareTimeIndex
            );
        }
    }


    //*******INTERNAL FUNCTIONS*********//
    function _testQueueWithdrawal(
        address depositor,
        IInvestmentStrategy[] memory strategyArray,
        IERC20[] memory tokensArray,
        uint256[] memory shareAmounts,
        uint256[] memory strategyIndexes,
        IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce
    )
        internal
        returns (bytes32)
    {
        cheats.startPrank(depositor);

        bytes32 withdrawalRoot = investmentManager.queueWithdrawal(
            strategyIndexes,
            strategyArray,
            tokensArray,
            shareAmounts,
            withdrawerAndNonce,
            // TODO: make this an input
            true
        );
        cheats.stopPrank();
        return withdrawalRoot;
    }

    function _testCompleteQueuedWithdrawalShares(
        address depositor,
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
        cheats.startPrank(withdrawerAndNonce.withdrawer);

        for (uint256 i = 0; i < strategyArray.length; i++) {
            sharesBefore.push(investmentManager.investorStratShares(withdrawerAndNonce.withdrawer, strategyArray[i]));

        }
        // emit log_named_uint("strategies", strategyArray.length);
        // emit log_named_uint("tokens", tokensArray.length);
        // emit log_named_uint("shares", shareAmounts.length);
        // emit log_named_address("depositor", depositor);
        // emit log_named_uint("withdrawalStartBlock", withdrawalStartBlock);
        // emit log_named_address("delegatedAddress", delegatedTo);
        // emit log("************************************************************************************************");

        IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal = IInvestmentManager.QueuedWithdrawal({
            strategies: strategyArray,
            tokens: tokensArray,
            shares: shareAmounts,
            depositor: depositor,
            withdrawerAndNonce: withdrawerAndNonce,
            withdrawalStartBlock: withdrawalStartBlock,
            delegatedAddress: delegatedTo
        });

        // complete the queued withdrawal
        investmentManager.completeQueuedWithdrawal(queuedWithdrawal, middlewareTimesIndex, false);

        for (uint256 i = 0; i < strategyArray.length; i++) {
            require(
                investmentManager.investorStratShares(withdrawerAndNonce.withdrawer, strategyArray[i])
                    == sharesBefore[i] + shareAmounts[i],
                "_testCompleteQueuedWithdrawalShares: withdrawer shares not incremented"
            );
        }
        cheats.stopPrank();
    }
}