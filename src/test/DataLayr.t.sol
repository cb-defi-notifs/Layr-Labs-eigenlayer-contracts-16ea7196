// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Deployer.t.sol";
import "forge-std/Test.sol";


contract DataLayrTests is
    DSTest,
    EigenLayrDeployer
{
    //checks that it is possible to init a data store
    function testInitDataStore() public returns (bytes32) {
        return _testInitDataStore().metadata.headerHash;
    }

    function testInitDataStoreLoop() public{
        uint g = gasleft();
        for(uint i=0; i<20; i++){
            testInitDataStore();
        }
        emit log_named_uint("gas", g - gasleft());
    }
    
    //verifies that it is possible to confirm a data store
    //checks that the store is marked as committed
    function testLConfirmDataStore() public {
        _testConfirmDataStoreSelfOperators(15);
    }

    function testConfirmDataStoreLoop() public{
        _testConfirmDataStoreSelfOperators(15);
        uint g = gasleft();
        for(uint i=0; i<20; i++){
            _testConfirmDataStoreWithoutRegister();
        }
        emit log_named_uint("gas", g - gasleft());
    }

    // function testConfirmDataStoreTwoOperators() public {
    //     _testConfirmDataStoreSelfOperators(2);
    // }

    // function testConfirmDataStoreTwelveOperators() public {
    //     _testConfirmDataStoreSelfOperators(12);
    // }
}