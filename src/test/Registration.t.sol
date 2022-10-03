// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;


import "./TestHelper.t.sol";

contract RegistrationTests is TestHelper {

    function testBLSRegistration() public{
        emit log_address(sample_registrant);

        bytes memory data = abi.encodePacked(
            sample_pk[0],
            sample_pk[1],
            sample_pk[2],
            sample_pk[3],
            sample_sig[0],
            sample_sig[1]
        );
        cheats.startPrank(sample_registrant);
        blsPkCompendium.registerBLSPublicKey(data);
        cheats.stopPrank();
    }
}

