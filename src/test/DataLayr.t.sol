// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./DataLayrTestHelper.t.sol";
import "forge-std/Test.sol";

contract DataLayrTests is DSTest, DataLayrTestHelper {
    //checks that it is possible to init a data store
    function testInitDataStore() public returns (bytes32) {
        //change the current timestamp to be in the future 100 seconds and init
        return _testInitDataStore(block.timestamp + 100, address(this)).metadata.headerHash;
    }

    function testLoopInitDataStore() public {
        uint256 g = gasleft();
        for (uint256 i = 0; i < 20; i++) {
            testInitDataStore();
        }
        emit log_named_uint("gas", g - gasleft());
    }

    //verifies that it is possible to confirm a data store
    //checks that the store is marked as committed
    function testConfirmDataStore() public {
        _testConfirmDataStoreSelfOperators(15);
    }

    function testLoopConfirmDataStoreLoop() public {
        _testConfirmDataStoreSelfOperators(15);
        uint256 g = gasleft();
        for (uint256 i = 1; i < 5; i++) {
            _testConfirmDataStoreWithoutRegister(block.timestamp, i, 15);
        }
        emit log_named_uint("gas", g - gasleft());
    }

    function testConfirmDataStoreTwoOperators() public {
        _testConfirmDataStoreSelfOperators(2);
    }

    function testConfirmDataStoreTwelveOperators() public {
        _testConfirmDataStoreSelfOperators(12);
    }
}
