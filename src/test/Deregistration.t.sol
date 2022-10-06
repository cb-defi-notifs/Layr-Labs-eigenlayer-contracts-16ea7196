// SPDX-License-Verifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Registration.t.sol";
import "../contracts/libraries/BytesLib.sol";

contract DeregistrationTests is TestHelper {
    using BytesLib for bytes;

    function testBLSDeregistration(
    uint8 operatorIndex,
    uint256 ethAmount, 
    uint256 eigenAmount
    ) public {

        //RegistrationTests.testBLSRegistration(operatorIndex, ethAmount, eigenAmount);

        // uint256[4] memory pubkeyToRemoveAff; 
        // pubkeyToRemoveAff[0] = uint256(bytes32(registrationData[operatorIndex].slice(32,32)));
        // pubkeyToRemoveAff[1] = uint256(bytes32(registrationData[operatorIndex].slice(0,32)));
        // pubkeyToRemoveAff[2] = uint256(bytes32(registrationData[operatorIndex].slice(96,32)));
        // pubkeyToRemoveAff[3] = uint256(bytes32(registrationData[operatorIndex].slice(64,32)));
                            

        // _testDeregisterOperatorWithDataLayr(operatorIndex, pubkeyToRemoveAff, uint8(dlReg.numOperators())-1, testEphemeralKey);


    }


}