// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Deployer.t.sol";

contract DataLayrTests is
    EigenLayrDeployer
{
    //checks that it is possible to init a data store
    function testInitDataStore() public returns (bytes32) {
        return _testInitDataStore();
    }
    
    //verifies that it is possible to confirm a data store
    //checks that the store is marked as committed
    function testConfirmDataStore() public {
        _testConfirmDataStoreSelfOperators(15);
    }

    // function testConfirmDataStoreTwoOperators() public {
    //     _testConfirmDataStoreSelfOperators(2);
    // }

    // function testConfirmDataStoreTwelveOperators() public {
    //     _testConfirmDataStoreSelfOperators(12);
    // }
}
