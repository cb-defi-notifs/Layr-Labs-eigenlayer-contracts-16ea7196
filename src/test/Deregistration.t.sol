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

        BLSRegistration(operatorIndex, ethAmount, eigenAmount);

        uint256[4] memory pubkeyToRemoveAff; 
        pubkeyToRemoveAff[0] = uint256(bytes32(registrationData[operatorIndex].slice(32,32)));
        pubkeyToRemoveAff[1] = uint256(bytes32(registrationData[operatorIndex].slice(0,32)));
        pubkeyToRemoveAff[2] = uint256(bytes32(registrationData[operatorIndex].slice(96,32)));
        pubkeyToRemoveAff[3] = uint256(bytes32(registrationData[operatorIndex].slice(64,32)));

        emit log_named_uint("numoperators", dlReg.numOperators());
                            

        _testDeregisterOperatorWithDataLayr(operatorIndex, pubkeyToRemoveAff, uint8(dlReg.numOperators()-1), testEphemeralKey);


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


}