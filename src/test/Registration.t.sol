// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;


import "./TestHelper.t.sol";

contract RegistrationTests is TestHelper {

    function testBLSRegistration() public{
        emit log_address(sample_registrant);

        bytes memory data = abi.encodePacked(
            registrationData[0]
        );
        cheats.startPrank(signers[0]);
        blsPkCompendium.registerBLSPublicKey(data);
        cheats.stopPrank();
    }
}

