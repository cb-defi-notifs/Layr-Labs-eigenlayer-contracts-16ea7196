// SPDX-License-Verifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Registration.t.sol";

contract DeregistrationTests is RegistrationTests {

    function testBLSDeregistration(
    uint8 operatorIndex,
    uint256 ethAmount, 
    uint256 eigenAmount
    ) public {
        testBLSRegistration(operatorIndex, ethAmount, eigenAmount);

    }


}