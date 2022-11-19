// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../test/DataLayrTestHelper.t.sol";

import "../contracts/libraries/BytesLib.sol";

import "./mocks/MiddlewareRegistryMock.sol";
import "./mocks/ServiceManagerMock.sol";
import "./Delegation.t.sol";

contract WithdrawalTests is DelegationTests {

    MiddlewareRegistryMock public generalReg1;
    ServiceManagerMock public generalServiceManager1;

    MiddlewareRegistryMock public generalReg2;
    ServiceManagerMock public generalServiceManager2;

    function initializeMiddlewares() public {
        generalServiceManager1 = new ServiceManagerMock();

        generalReg1 = new MiddlewareRegistryMock(
             generalServiceManager1,
             investmentManager
        );
        
        generalServiceManager2 = new ServiceManagerMock();

        generalReg2 = new MiddlewareRegistryMock(
             generalServiceManager2,
             investmentManager
        );
    }

    //This function helps with stack too deep issues with "testWithdrawal" test
    function testWithdrawalWrapper(
            address operator, 
            address depositor,
            address withdrawer, 
            uint256 ethAmount,
            uint256 eigenAmount,
            bool withdrawAsTokens,
            bool RANDAO
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

            if(RANDAO){
                _testWithdrawalAndDeregistration(operator, depositor, withdrawer, ethAmount, eigenAmount, withdrawAsTokens);
            }
            else{
                _testWithdrawalWithStakeUpdate(operator, depositor, withdrawer, ethAmount, eigenAmount, withdrawAsTokens);
            }

        }

    /// @notice test staker's ability to undelegate/withdraw from an operator.
    /// @param operator is the operator being delegated to.
    /// @param depositor is the staker delegating stake to the operator.
    function _testWithdrawalAndDeregistration(
            address operator, 
            address depositor,
            address withdrawer, 
            uint256 ethAmount,
            uint256 eigenAmount,
            bool withdrawAsTokens
        ) 
            internal 
        {

        testDelegation(operator, depositor, ethAmount, eigenAmount);

        cheats.startPrank(operator);
        investmentManager.slasher().optIntoSlashing(address(generalServiceManager1));
        cheats.stopPrank();

        generalReg1.registerOperator(operator, uint32(block.timestamp) + 3 days);

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
        
        generalReg1.deregisterOperator(operator);
        {
            //warp past the serve until time, which is 3 days from the beginning.  THis puts us at 4 days past that point
            cheats.warp(uint32(block.timestamp) + 4 days);
            cheats.roll(uint32(block.timestamp) + 4 days);

            uint256 middlewareTimeIndex =  1;
            if (withdrawAsTokens) {
                _testCompleteQueuedWithdrawalTokens(
                    depositor,
                    dataForTestWithdrawal.delegatorStrategies,
                    tokensArray,
                    dataForTestWithdrawal.delegatorShares,
                    delegatedTo,
                    dataForTestWithdrawal.withdrawerAndNonce,
                    queuedWithdrawalBlock,
                    middlewareTimeIndex
                );
            } else {
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
    }

    /// @notice test staker's ability to undelegate/withdraw from an operator.
    /// @param operator is the operator being delegated to.
    /// @param depositor is the staker delegating stake to the operator.
    function _testWithdrawalWithStakeUpdate(
            address operator, 
            address depositor,
            address withdrawer, 
            uint256 ethAmount,
            uint256 eigenAmount,
            bool withdrawAsTokens
        ) 
            public 
        {
        testDelegation(operator, depositor, ethAmount, eigenAmount);

        cheats.startPrank(operator);
        investmentManager.slasher().optIntoSlashing(address(generalServiceManager1));
        investmentManager.slasher().optIntoSlashing(address(generalServiceManager2));
        cheats.stopPrank();

        // emit log_named_uint("Linked list element 1", uint256(uint160(address(generalServiceManager1))));
        // emit log_named_uint("Linked list element 2", uint256(uint160(address(generalServiceManager2))));
        // emit log("________________________________________________________________");
        generalReg1.registerOperator(operator, uint32(block.timestamp) + 5 days);
        // emit log_named_uint("Middleware 1 Update Block", uint32(block.number));

        cheats.warp(uint32(block.timestamp) + 1 days);
        cheats.roll(uint32(block.number) + 1);

        generalReg2.registerOperator(operator, uint32(block.timestamp) + 5 days);
        // emit log_named_uint("Middleware 2 Update Block", uint32(block.number));

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
        cheats.roll(uint32(block.number) + 1);

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
        cheats.roll(uint32(block.number) + 2);

        
        uint256 prevElement = uint256(uint160(address(generalServiceManager2)));
        generalReg1.propagateStakeUpdate(operator, uint32(block.number), prevElement);

        cheats.warp(uint32(block.timestamp) + 1 days);
        cheats.roll(uint32(block.number) + 1);

        prevElement = uint256(uint160(address(generalServiceManager1)));
        generalReg2.propagateStakeUpdate(operator, uint32(block.number), prevElement);
        
        {
            //warp past the serve until time, which is 3 days from the beginning.  THis puts us at 4 days past that point
            cheats.warp(uint32(block.timestamp) + 4 days);
            cheats.roll(uint32(block.number) + 4);

            uint256 middlewareTimeIndex =  3;
            if (withdrawAsTokens) {
                _testCompleteQueuedWithdrawalTokens(
                    depositor,
                    dataForTestWithdrawal.delegatorStrategies,
                    tokensArray,
                    dataForTestWithdrawal.delegatorShares,
                    delegatedTo,
                    dataForTestWithdrawal.withdrawerAndNonce,
                    queuedWithdrawalBlock,
                    middlewareTimeIndex
                );
            } else {
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
    }
    // @notice This function tests to ensure that a delegator can re-delegate to an operator after undelegating.
    // @param operator is the operator being delegated to.
    // @param staker is the staker delegating stake to the operator.
    function testRedelegateAfterWithdrawal(
            address operator, 
            address depositor, 
            address withdrawer, 
            uint256 ethAmount, 
            uint256 eigenAmount,
            bool withdrawAsShares
        ) 
            public
            fuzzedAddress(operator) 
            fuzzedAddress(depositor)
            fuzzedAddress(withdrawer)
        {
        cheats.assume(depositor != operator);
        //this function performs delegation and subsequent withdrawal
        testWithdrawalWrapper(operator, depositor, withdrawer, ethAmount, eigenAmount, withdrawAsShares, true);

        //warps past fraudproof time interval
        cheats.warp(block.timestamp + undelegationFraudproofInterval + 1);
        testDelegation(operator, depositor, ethAmount, eigenAmount);
    }

    /// @notice test to see if an operator who is slashed/frozen
    ///         cannot be undelegated from by their stakers.
    /// @param operator is the operator being delegated to.
    /// @param staker is the staker delegating stake to the operator.
    function testSlashedOperatorWithdrawal(address operator, address staker, uint256 ethAmount, uint256 eigenAmount)
        public
        fuzzedAddress(operator)
        fuzzedAddress(staker)
    {
        cheats.assume(staker != operator);
        testDelegation(operator, staker, ethAmount, eigenAmount);

        address slashingContract = slasher.owner();

        address[] memory slashingContracts = new address[](1);
        slashingContracts[0] = slashingContract;

        cheats.startPrank(slashingContract);
        slasher.addGloballyPermissionedContracts(slashingContracts);
        slasher.freezeOperator(operator);
        cheats.stopPrank();

        (IInvestmentStrategy[] memory updatedStrategies, uint256[] memory updatedShares) =
            investmentManager.getDeposits(staker);

        IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce =
            IInvestmentManager.WithdrawerAndNonce({withdrawer: staker, nonce: 0});

        uint256[] memory strategyIndexes = new uint256[](2);
        strategyIndexes[0] = 0;
        strategyIndexes[1] = 1;

        IERC20[] memory tokensArray = new IERC20[](2);
        tokensArray[0] = weth;
        tokensArray[0] = eigenToken;

        //initiating queued withdrawal
        cheats.expectRevert(
            bytes("InvestmentManager.onlyNotFrozen: staker has been frozen and may be subject to slashing")
        );
        _testQueueWithdrawal(staker, updatedStrategies, tokensArray, updatedShares, strategyIndexes, withdrawerAndNonce);
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
}