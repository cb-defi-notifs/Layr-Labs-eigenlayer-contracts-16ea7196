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
    EigenDARegistryMock public eigenDARegImplementation;
    ServiceManagerMock public eigenDASM;

    bytes32 public testEphemeralKey1 = 0x3290567812345678123456781234577812345698123456781234567812344389;
    bytes32 public testEphemeralKeyHash1 = keccak256(abi.encode(testEphemeralKey1));
    bytes32 public testEphemeralKey2 = 0x9890567812345678123456780094577812345698123456781234563849087560;
    bytes32 public testEphemeralKeyHash2 = keccak256(abi.encode(testEphemeralKey2));

    bytes32[] public ephemeralKeys;

    modifier initialized(address operator){
        initializeMiddlewares();
        cheats.startPrank(operator);
        investmentManager.slasher().optIntoSlashing(address(eigenDASM));
        cheats.stopPrank();
        _;
    }


    function initializeMiddlewares() public {
        eigenDASM = new ServiceManagerMock(investmentManager);

        eigenDAReg = EigenDARegistryMock(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );

        ephemeralKeyRegistry = new EphemeralKeyRegistry(eigenDAReg, eigenDASM);


        eigenDARegImplementation = new EigenDARegistryMock(
             eigenDASM,
             investmentManager,
             ephemeralKeyRegistry
        );

        eigenLayrProxyAdmin.upgrade(
                TransparentUpgradeableProxy(payable(address(eigenDAReg))),
                address(eigenDARegImplementation)
        );

        ephemeralKeys.push(testEphemeralKey1);
        ephemeralKeys.push(testEphemeralKey2);
    }

    function testSlashStaleEphemeralKey(address operator) public initialized(operator) {
        cheats.startPrank(address(eigenDAReg));
        ephemeralKeyRegistry.postFirstEphemeralKeyHashes(operator, testEphemeralKeyHash1, testEphemeralKeyHash2);
       
        //roll past the ephemeralKey2's start block and then another USAGE_PERIOD beyond that
        cheats.roll(block.number + 648000*2 + 1);

        ephemeralKeyRegistry.verifyStaleEphemeralKey(operator, 1);
        require(investmentManager.slasher().isFrozen(operator), "operator not frozen successfully");
        cheats.stopPrank();
    }

    //This function helps with stack too deep issues with "testWithdrawal" test
    function testEKWithdrawalWrapper(
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

            _testWithdrawalAndDeregistrationEphemeralKeys(operator, depositor, withdrawer, ethAmount, eigenAmount);
        }

    /// @notice test staker's ability to undelegate/withdraw from an operator.
    /// @param operator is the operator being delegated to.
    /// @param depositor is the staker delegating stake to the operator.
    function _testWithdrawalAndDeregistrationEphemeralKeys(
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
        investmentManager.slasher().optIntoSlashing(address(eigenDASM));
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


        uint256 startIndex = 0;
        eigenDAReg.deregisterOperator(operator, ephemeralKeys, startIndex);
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
}