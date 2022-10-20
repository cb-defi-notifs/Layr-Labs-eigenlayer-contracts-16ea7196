// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./TestHelper.t.sol";
import "forge-std/Test.sol";

contract DataLayrTests is DSTest, TestHelper {
    //checks that it is possible to init a data store
    function testInitDataStore() public returns (bytes32) {
        uint256 numSigners = 15;

        //register all the operators
        _registerNumSigners(numSigners);

        //change the current timestamp to be in the future 100 seconds and init
        return _testInitDataStore(block.timestamp + 100, address(this)).metadata.headerHash;
    }

    function testLoopInitDataStore() public {
        uint256 g = gasleft();
        uint256 numSigners = 15;

        for (uint256 i = 0; i < 20; i++) {
            if(i==0){
                _registerNumSigners(numSigners);
            }
            _testInitDataStore(block.timestamp + 100, address(this)).metadata.headerHash;
        }
        emit log_named_uint("gas", g - gasleft());
    }

    //verifies that it is possible to confirm a data store
    //checks that the store is marked as committed
    function testConfirmDataStore() public {
        _testConfirmDataStoreSelfOperators(15);
    }

    function testConfirmDataStoreLoop() public {
        _testConfirmDataStoreSelfOperators(15);
        uint256 g = gasleft();
        for (uint256 i = 1; i < 5; i++) {
            _testConfirmDataStoreWithoutRegister(block.timestamp, i, 15);
        }
        emit log_named_uint("gas", g - gasleft());
    }

    function testConfirmDataStoreTwelveOperators() public {
        _testConfirmDataStoreSelfOperators(12);
    }

    function testCodingRatio() public {

        uint256 numSigners = 15;
        //register all the operators
        _registerNumSigners(numSigners);

        /// @notice this header has numSys set to 9.  Thus coding ration = 9/15, which is greater than the set adversary threshold in DataLayrServiceManager.
        bytes memory header = hex"0e75f28b7a90f89995e522d0cd3a340345e60e249099d4cd96daef320a3abfc31df7f4c8f6f8bc5dc1de03f56202933ec2cc40acad1199f40c7b42aefd45bfb10000000800000009000000020000014000000000000000000000000000000000000000002b4982b07d4e522c2a94b3e7c5ab68bfeecc33c5fa355bc968491c62c12cf93f0cd04099c3d9742620bf0898cf3843116efc02e6f7d408ba443aa472f950e4f3";
        
        uint256 initTimestamp = block.timestamp + 100;

        // weth is set as the paymentToken of dlsm, so we must approve dlsm to transfer weth
        weth.transfer(storer, 1e11);
        cheats.startPrank(storer);
        weth.approve(address(dataLayrPaymentManager), type(uint256).max);

        dataLayrPaymentManager.depositFutureFees(storer, 1e11);

        uint32 blockNumber = uint32(block.number);
        uint32 totalOperatorsIndex = uint32(dlReg.getLengthOfTotalOperatorsHistory() - 1);

        require(initTimestamp >= block.timestamp, "_testInitDataStore: warping back in time!");
        cheats.warp(initTimestamp);
        uint256 timestamp = block.timestamp;

        cheats.expectRevert(bytes("DataLayrServiceManager.initDataStore: Coding ratio is too high"));
        uint32 index = dlsm.initDataStore(
            storer,
            address(this),
            durationToInit,
            blockNumber,
            totalOperatorsIndex,
            header
        );
    }

    function testZeroTotalBytes() public {
        bytes memory header = hex"0e75f28b7a90f89995e522d0cd3a340345e60e249099d4cd96daef320a3abfc31df7f4c8f6f8bc5dc1de03f56202933ec2cc40acad1199f40c7b42aefd45bfb10000000800000002000000020000014000000000000000000000000000000000000000002b4982b07d4e522c2a94b3e7c5ab68bfeecc33c5fa355bc968491c62c12cf93f0cd04099c3d9742620bf0898cf3843116efc02e6f7d408ba443aa472f950e4f3";
        
        uint256 initTimestamp = block.timestamp + 100;

        // weth is set as the paymentToken of dlsm, so we must approve dlsm to transfer weth
        weth.transfer(storer, 1e11);
        cheats.startPrank(storer);
        weth.approve(address(dataLayrPaymentManager), type(uint256).max);

        dataLayrPaymentManager.depositFutureFees(storer, 1e11);

        uint32 blockNumber = uint32(block.number);
        uint32 totalOperatorsIndex = uint32(dlReg.getLengthOfTotalOperatorsHistory() - 1);

        require(initTimestamp >= block.timestamp, "_testInitDataStore: warping back in time!");
        cheats.warp(initTimestamp);
        uint256 timestamp = block.timestamp;

        cheats.expectRevert(bytes("DataLayrServiceManager.initDataStore: totalBytes < MIN_STORE_SIZE"));
        uint32 index = dlsm.initDataStore(
            storer,
            address(this),
            durationToInit,
            blockNumber,
            totalOperatorsIndex,
            header
        );
    }

    function testTotalOperatorIndexExceedingHistoryLength(uint32 wrongTotalOperatorIndex) public {
        cheats.assume(wrongTotalOperatorIndex >= uint32(dlReg.getLengthOfTotalOperatorsHistory()));
        bytes memory revertMsg = bytes("RegistryBase.getTotalOperators: TotalOperator indexHistory index exceeds array length");
    }


    function _testTotalOperatorIndex(uint32 wrongTotalOperatorsIndex, bytes memory revertMsg) internal {
        uint256 numSigners = 15;
        //register all the operators
        _registerNumSigners(numSigners);
        bytes memory header = hex"0e75f28b7a90f89995e522d0cd3a340345e60e249099d4cd96daef320a3abfc31df7f4c8f6f8bc5dc1de03f56202933ec2cc40acad1199f40c7b42aefd45bfb10000000800000002000000020000014000000000000000000000000000000000000000002b4982b07d4e522c2a94b3e7c5ab68bfeecc33c5fa355bc968491c62c12cf93f0cd04099c3d9742620bf0898cf3843116efc02e6f7d408ba443aa472f950e4f3";
        
        uint256 initTimestamp = block.timestamp + 100;

        // weth is set as the paymentToken of dlsm, so we must approve dlsm to transfer weth
        weth.transfer(storer, 1e11);
        cheats.startPrank(storer);
        weth.approve(address(dataLayrPaymentManager), type(uint256).max);

        dataLayrPaymentManager.depositFutureFees(storer, 1e11);

        uint32 blockNumber = uint32(block.number);
        uint32 totalOperatorsIndex = uint32(dlReg.getLengthOfTotalOperatorsHistory() - 1);

        require(initTimestamp >= block.timestamp, "_testInitDataStore: warping back in time!");
        cheats.warp(initTimestamp);
        uint256 timestamp = block.timestamp;

        cheats.expectRevert(revertMsg);
        uint32 index = dlsm.initDataStore(
            storer,
            address(this),
            durationToInit,
            blockNumber,
            wrongTotalOperatorsIndex,
            header
        );


    }

    //This function generates the msgBytes that can be used to generate signatures on using the dlutils CLI or the AssortedScripts repo
    // function testGenerateMsgBytes() public {

    //     bytes memory header = hex"0e75f28b7a90f89995e522d0cd3a340345e60e249099d4cd96daef320a3abfc31df7f4c8f6f8bc5dc1de03f56202933ec2cc40acad1199f40c7b42aefd45bfb10000000800000002000000020000014000000000000000000000000000000000000000002b4982b07d4e522c2a94b3e7c5ab68bfeecc33c5fa355bc968491c62c12cf93f0cd04099c3d9742620bf0898cf3843116efc02e6f7d408ba443aa472f950e4f3";
    //     bytes32 headerHash = keccak256(header);
    //     uint8 duration = 2;
    //     uint256 initTime = 1000000001;
    //     uint32 index = 4;
    //     uint32 globalDataStoreId = 5;
    //     bytes memory msgBytes =  abi.encodePacked(
    //                             globalDataStoreId,
    //                             headerHash,
    //                             duration,
    //                             initTime,
    //                             index
    //                         );
    //     emit log_named_bytes("msgBytes", msgBytes);
    //}

    function _registerNumSigners(uint256 numSigners) internal {
        for (uint256 i = 0; i < numSigners; ++i) {
            _testRegisterAdditionalSelfOperator(signers[i], registrationData[i], ephemeralKeyHashes[i]);
        }
    }
}
