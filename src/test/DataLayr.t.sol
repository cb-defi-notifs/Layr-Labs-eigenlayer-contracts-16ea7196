// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./TestHelper.t.sol";
import "forge-std/Test.sol";

contract DataLayrTests is DSTest, TestHelper {
    //checks that it is possible to init a data store
    function testInitDataStore() public returns (bytes32) {
        uint256 numSigners = 15;

        //register all the operators
        for (uint256 i = 0; i < numSigners; ++i) {
            _testRegisterAdditionalSelfOperator(signers[i], registrationData[i], ephemeralKeyHashes[i]);
        }
        
        //change the current timestamp to be in the future 100 seconds and init
        return _testInitDataStore(block.timestamp + 100, address(this)).metadata.headerHash;
    }

    function testLoopInitDataStore() public {
        uint256 g = gasleft();
        uint256 numSigners = 15;

        for (uint256 i = 0; i < 20; i++) {
            if(i==0){
                for (uint256 i = 0; i < numSigners; ++i) {
                    _testRegisterAdditionalSelfOperator(signers[i], registrationData[i], ephemeralKeyHashes[i]);
                }
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

    }
    

    function testGenerateMsgBytes() public {

        bytes memory header = hex"0e75f28b7a90f89995e522d0cd3a340345e60e249099d4cd96daef320a3abfc31df7f4c8f6f8bc5dc1de03f56202933ec2cc40acad1199f40c7b42aefd45bfb10000000800000002000000020000014000000000000000000000000000000000000000002b4982b07d4e522c2a94b3e7c5ab68bfeecc33c5fa355bc968491c62c12cf93f0cd04099c3d9742620bf0898cf3843116efc02e6f7d408ba443aa472f950e4f3";
        bytes32 headerHash = keccak256(header);
        uint8 duration = 2;
        uint256 initTime = 1000000001;
        uint32 index = 4;
        uint32 globalDataStoreId = 5;
        bytes memory msgBytes =  abi.encodePacked(
                                globalDataStoreId,
                                headerHash,
                                duration,
                                initTime,
                                index
                            );
        emit log_named_bytes("msgBytes", msgBytes);
    }
}
