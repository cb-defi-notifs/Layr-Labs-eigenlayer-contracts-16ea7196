// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;


import "./TestHelper.t.sol";

contract RegistrationTests is TestHelper {

    function testBLSRegistration() public {
        emit log_address(sample_registrant);

        bytes memory data = abi.encodePacked(
            registrationData[0]
        );
        cheats.startPrank(signers[0]);
        blsPkCompendium.registerBLSPublicKey(data);
        cheats.stopPrank();
    }

    function testRegisterPublicKeyTwice(uint8 index) public {
        cheats.assume(index < registrationData.length);
        cheats.startPrank(signers[index]);
        //try to register the same pubkey twice
        pubkeyCompendium.registerBLSPublicKey(registrationData[index]);
        cheats.expectRevert("BLSPublicKeyRegistry.registerBLSPublicKey: operator already registered pubkey");
        pubkeyCompendium.registerBLSPublicKey(registrationData[index]);
    }

    // function testRegisterWhileAlreadyActive(uint8 whichIndex) public {
    //     cheats.assume(whichIndex < registrationData.length);
    //     _testInitiateDelegation(signers[whichIndex])
    //     cheats.startPrank(signers[whichIndex]);
    //     //try to register after already registered
    //     pubkeyCompendium.registerBLSPublicKey(registrationData[whichIndex]);
    //     dlReg.registerOperator()
    //     cheats.stopPrank();
    // }

}

