// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./TestHelper.t.sol";
import "../contracts/libraries/BytesLib.sol";

contract RegistrationTests is TestHelper {
    using BytesLib for bytes;

    function testBLSRegistration(
        uint8 operatorIndex,
        uint256 ethAmount, 
        uint256 eigenAmount
    ) fuzzedOperatorIndex(operatorIndex) public {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);
        
        uint8 operatorType = 1;
        // _testInitiateDelegation(
        //     operatorIndex,
        //     operatorType,
        //     testSocket,
        //     eigenAmount,
        //     ethAmount
        // );

        _testRegisterBLSPubKey(operatorIndex);

        bytes32 hashofPk = keccak256(
                              abi.encodePacked(
                                uint256(bytes32(registrationData[operatorIndex].slice(32,32))),
                                uint256(bytes32(registrationData[operatorIndex].slice(0,32))),
                                uint256(bytes32(registrationData[operatorIndex].slice(96,32))),
                                uint256(bytes32(registrationData[operatorIndex].slice(64,32)))
                              )
                            );

        require(pubkeyCompendium.operatorToPubkeyHash(signers[operatorIndex]) == hashofPk, "hash not stored correctly");
        require(pubkeyCompendium.pubkeyHashToOperator(hashofPk) == signers[operatorIndex], "hash not stored correctly");

        // _testRegisterOperatorWithDataLayr(
        //     operatorIndex,
        //     operatorType,
        //     testSocket
        // );


    }

    function testRegisterPublicKeyTwice(uint8 operatorIndex) fuzzedOperatorIndex(operatorIndex) public {
        cheats.startPrank(signers[operatorIndex]);
        //try to register the same pubkey twice
        pubkeyCompendium.registerBLSPublicKey(registrationData[operatorIndex]);
        cheats.expectRevert(
            "BLSPublicKeyRegistry.registerBLSPublicKey: operator already registered pubkey"
        );
        pubkeyCompendium.registerBLSPublicKey(registrationData[operatorIndex]);
    }

    function testRegisterWhileAlreadyActive(
        uint8 operatorIndex, 
        uint256 ethAmount, 
        uint256 eigenAmount
    ) fuzzedOperatorIndex(operatorIndex) public {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);
        
        uint8 operatorType = 3;
        _testInitiateDelegation(
            operatorIndex,
            operatorType,
            testSocket,
            eigenAmount,
            ethAmount
        );
        _testRegisterBLSPubKey(
            operatorIndex
        );
        _testRegisterOperatorWithDataLayr(
            operatorIndex,
            operatorType,
            testSocket
        );
        cheats.startPrank(signers[operatorIndex]);

        //try to register after already registered
        cheats.expectRevert(
            "RegistryBase._registrationStakeEvaluation: Operator is already registered"
        );
        dlReg.registerOperator(
            3,
            bytes32(0),
            registrationData[operatorIndex].slice(0, 128),
            testSocket
        );
        cheats.stopPrank();
    }

    // function testRegisterWhileAlreadyActive(uint8 operatorIndex, uint256 ethAmount, uint256 eigenAmount) public {
    //     cheats.assume(operatorIndex < registrationData.length);
    //     cheats.assume(ethAmount > 0 && ethAmount < 1e18);
    //     cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);
    //     _testInitiateDelegationAndRegisterOperatorWithDataLayr(operatorIndex, eigenAmount, ethAmount);
    //     cheats.startPrank(signers[operatorIndex]);
    //     //try to register after already registered
    //     cheats.expectRevert("RegistryBase._registrationStakeEvaluation: Operator is already registered");
    //     dlReg.registerOperator(3, testEphemeralKey, registrationData[operatorIndex].slice(0, 128), testSocket);
    //     cheats.stopPrank();
    // }

    //Test that when operator tries to register with DataLayr 
    // with a public key that they haven't registered in the BLSPublicKeyCompendium, it fails
    function testOperatorDoesNotOwnPublicKey(
        uint8 operatorIndex, 
        uint256 ethAmount, 
        uint256 eigenAmount
    ) fuzzedOperatorIndex(operatorIndex) public {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);

        uint8 operatorType = 1;
        _testInitiateDelegation(
            operatorIndex,
            operatorType,
            testSocket,
            eigenAmount,
            ethAmount
        );
        //registering the operator without having registered their BLS public key
        cheats.expectRevert(bytes("BLSRegistry._registerOperator: operator does not own pubkey"));

        _testRegisterOperatorWithDataLayr(
            operatorIndex,
            operatorType,
            testSocket
        );
    } 

    function testRegisterForDataLayrWithNeitherQuorum(
        uint8 operatorIndex,
        uint256 ethAmount,
        uint256 eigenAmount
    ) fuzzedOperatorIndex(operatorIndex) public {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);
        uint8 noQuorumOperatorType = 0;

        _testInitiateDelegation(
            operatorIndex,
            noQuorumOperatorType,
            testSocket,
            eigenAmount,
            ethAmount
        );
        _testRegisterBLSPubKey(
            operatorIndex
        );
        cheats.expectRevert(bytes("RegistryBase._registrationStakeEvaluation: Must register as at least one type of validator"));
        _testRegisterOperatorWithDataLayr(
            operatorIndex,
            noQuorumOperatorType,
            testSocket
        );
    }

    function testRegisteringWithSomeoneElsePubKey(
        uint8 operatorIndex,
        uint256 ethAmount,
        uint256 eigenAmount
    ) fuzzedOperatorIndex(operatorIndex) public {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);


    }

}
