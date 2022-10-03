// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;


import "./TestHelper.t.sol";

contract RegistrationTests is TestHelper {

    function testBLSRegistration() public{

        bytes memory data = abi.encodePacked(
            pk[0],
            pk[1],
            pk[2],
            pk[3],
            sigma[0],
            sigma[1]
        );
    }
}

