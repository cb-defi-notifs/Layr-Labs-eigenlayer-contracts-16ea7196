// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "ds-test/test.sol";
import "../test/Delegation.t.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";



contract Disclosure is Delegator {
    using BytesLib for bytes;
    using Math for uint;


    
    function testForcedDisclosure() public{

        //register signers
        uint32 numberOfSigners = 15;
        _testRegisterSigners(numberOfSigners, true);
        
    
    
        bytes32 headerHash = _testInitDataStore();
        uint32 currentDumpNumber = dlsm.dumpNumber() - 1;
        uint32 numberOfNonSigners = 0;

        _testCommitDataStore( headerHash,  currentDumpNumber,  numberOfNonSigners,apks, sigmas);

    }


    


}