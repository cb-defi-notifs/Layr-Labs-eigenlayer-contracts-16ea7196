// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


import "./TestHelper.t.sol";
import "../contracts/libraries/BytesLib.sol";

contract RegistrationTests is TestHelper {
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
        cheats.expectRevert("BLSPublicKeyRegistry.registerBLSPublicKey: operator already registered pubkey");
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
        _testInitiateDelegationAndRegisterOperatorWithDataLayr(operatorIndex, operatorType, testSocket, eigenAmount, ethAmount);
        cheats.startPrank(signers[operatorIndex]);

        //try to register after already registered
        cheats.expectRevert("RegistryBase._registrationStakeEvaluation: Operator is already registered");
        dlReg.registerOperator(3, bytes32(0), registrationData[operatorIndex].slice(0, 128), testSocket);
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

}

