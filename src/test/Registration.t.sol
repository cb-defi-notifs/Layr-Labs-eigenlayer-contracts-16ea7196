// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./RevertTestHelper.t.sol";
import "../contracts/libraries/BytesLib.sol";

contract RegistrationTests is RevertTestHelper {
    using BytesLib for bytes;

    function testBLSRegistration(uint8 operatorIndex) fuzzedOperatorIndex(operatorIndex) public {
        address sender = signers[operatorIndex];
        bytes memory data = abi.encodePacked(
            registrationData[operatorIndex]
        );
        cheats.startPrank(sender);
        blsPkCompendium.registerBLSPublicKey(data);
        cheats.stopPrank();

        bytes32 hashofPk = keccak256(
                              abi.encodePacked(
                                uint256(bytes32(registrationData[operatorIndex].slice(32,32))),
                                uint256(bytes32(registrationData[operatorIndex].slice(0,32))),
                                uint256(bytes32(registrationData[operatorIndex].slice(96,32))),
                                uint256(bytes32(registrationData[operatorIndex].slice(64,32)))
                              )
                            );

        require(blsPkCompendium.operatorToPubkeyHash(sender) == hashofPk, "hash not stored correctly");
        require(blsPkCompendium.pubkeyHashToOperator(hashofPk) == sender, "hash not stored correctly");


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

        //TODO: @Sidu28 why doesn't fuzzing work here?
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
        _testRegisterWithDataLayr(
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





    } 

    function testRegisterForDataLayrWithNeitherQuorum(
        uint8 operatorIndex,
        uint256 ethAmount,
        uint256 eigenAmount
    ) fuzzedOperatorIndex(operatorIndex) public {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);

        uint8 noQuorumOperatorType = 0;
        _testShouldRevertRegisterOperatorWithDataLayr(
            operatorIndex,
            noQuorumOperatorType,
            testSocket,
            eigenAmount,
            ethAmount,
            "RegistryBase._registrationStakeEvaluation: Must register as at least one type of validator"
        );
    }
}
