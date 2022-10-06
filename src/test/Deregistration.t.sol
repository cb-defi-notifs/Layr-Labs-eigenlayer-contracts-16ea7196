// SPDX-License-Verifier: UNLICENSED
pragma solidity ^0.8.9;

import "./TestHelper.t.sol";
import "../contracts/libraries/BytesLib.sol";

contract DeregistrationTests is TestHelper {
    using BytesLib for bytes;

    function testBLSDeregistration(
        uint8 operatorIndex,
        uint256 ethAmount, 
        uint256 eigenAmount
    ) public fuzzedOperatorIndex(operatorIndex) {

        //TODO: probably a stronger test would be to register a few operators and then ensure that apk is updated correctly
        uint256[4] memory prevAPK;
        prevAPK[0] = dlReg.apk(0);
        prevAPK[1] = dlReg.apk(1);
        prevAPK[2] = dlReg.apk(2);
        prevAPK[3] = dlReg.apk(3);
        bytes32 prevAPKHash = BLS.hashPubkey(prevAPK);

        BLSRegistration(operatorIndex, ethAmount, eigenAmount);


        uint256[4] memory pubkeyToRemoveAff = getG2PKOfRegistrationData(operatorIndex);

        bytes32 pubkeyHash = BLS.hashPubkey(pubkeyToRemoveAff);                          

        _testDeregisterOperatorWithDataLayr(operatorIndex, pubkeyToRemoveAff, uint8(dlReg.numOperators()-1), testEphemeralKey);

        (,uint32 nextUpdateBlocNumber,,) = dlReg.pubkeyHashToStakeHistory(pubkeyHash, dlReg.getStakeHistoryLength(pubkeyHash)-1);
        require( nextUpdateBlocNumber == 0, "Stake history not updated correctly");

        bytes32 currAPKHash = dlReg.apkHashes(dlReg.getApkHashesLength()-1);
        require(currAPKHash == prevAPKHash, "aggregate public key has not been updated correctly following deregistration");

    }

    function testMismatchedPubkeyHashAndProvidedPubkeyHash(
        uint8 operatorIndex,
        uint256 ethAmount, 
        uint256 eigenAmount,
        uint256[4] memory pubkeyToRemoveAff
    ) public fuzzedOperatorIndex(operatorIndex) {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);
        cheats.assume(BLS.hashPubkey(pubkeyToRemoveAff) != BLS.hashPubkey(getG2PKOfRegistrationData(operatorIndex)));

    
        BLSRegistration(operatorIndex, ethAmount, eigenAmount);
        uint8 operatorListIndex = uint8(dlReg.numOperators()-1);
        cheats.expectRevert(bytes("BLSRegistry._deregisterOperator: pubkey input does not match stored pubkeyHash"));
        _testDeregisterOperatorWithDataLayr(operatorIndex, pubkeyToRemoveAff, operatorListIndex, testEphemeralKey);
    }

    function testEphemeralKeyDoesNotMatchPostedHash(
        uint8 operatorIndex,
        uint256 ethAmount, 
        uint256 eigenAmount,
        bytes32 badEphemeralKey
    ) public fuzzedOperatorIndex(operatorIndex) {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);
        cheats.assume(badEphemeralKey != testEphemeralKey);

        BLSRegistration(operatorIndex, ethAmount, eigenAmount);

        uint256[4] memory pubkeyToRemoveAff = getG2PKOfRegistrationData(operatorIndex);
        uint8 operatorListIndex = uint8(dlReg.numOperators()-1);
        cheats.expectRevert(bytes("EphemeralKeyRegistry.postLastEphemeralKeyPreImage: Ephemeral key does not match previous ephemeral key commitment"));
        _testDeregisterOperatorWithDataLayr(operatorIndex, pubkeyToRemoveAff, operatorListIndex, badEphemeralKey);
    }

    


        





    /// @notice Helper function that performs registration 
    function BLSRegistration(
        uint8 operatorIndex,
        uint256 ethAmount, 
        uint256 eigenAmount
    ) internal fuzzedOperatorIndex(operatorIndex) {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);
        
        uint8 operatorType = 3;
        _testInitiateDelegation(
            operatorIndex,
            eigenAmount,
            ethAmount
        );
        _testRegisterBLSPubKey(operatorIndex);
        _testRegisterOperatorWithDataLayr(
            operatorIndex,
            operatorType,
            testEphemeralKeyHash,
            testSocket
        );

    }

    function getG2PKOfRegistrationData(uint8 operatorIndex) internal returns(uint256[4] memory){
        uint256[4] memory pubkey; 
        pubkey[0] = uint256(bytes32(registrationData[operatorIndex].slice(32,32)));
        pubkey[1] = uint256(bytes32(registrationData[operatorIndex].slice(0,32)));
        pubkey[2] = uint256(bytes32(registrationData[operatorIndex].slice(96,32)));
        pubkey[3] = uint256(bytes32(registrationData[operatorIndex].slice(64,32)));
        return pubkey;
    }

}