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



        // verify sig of public key and get pubkeyHash back, slice out compressed apk
        bytes32 pkHash =getG2PublicKeyHash(data);

        require(blsPkCompendium.operatorToPubkeyHash(signers[0]) == pkHash, "operator to pubkey hash stored incorrectly");
    }

    function getG2PublicKeyHash(bytes memory data)  public returns(bytes32 pkHash){


        bytes calldata hashData = abi.encodePacked(registrationData[0]);
        uint256[4] memory pk;

        pk[0] = hashData[0:32];
        pk[1] = hashData[32:64];
        pk[2] = hashData[64:96];
        pk[3] = hashData[96:128];

        emit log_named_uint("pk[0]", pk[0]);
        emit log_named_uint("pk[1]", pk[1]);
        emit log_named_uint("pk[2]", pk[2]);
        emit log_named_uint("pk[3]", pk[3]);




        //pkHash = keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3]));

        return pkHash;

    }

}

