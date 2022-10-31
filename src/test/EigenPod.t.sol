//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./TestHelper.t.sol";
import "../contracts/interfaces/IEigenPod.sol";


contract EigenPodTests is TestHelper {

    bytes pubkey = hex"88347ed1c492eedc97fc8c506a35d44d81f27a0c7a1c661b35913cfd15256c0cccbd34a83341f505c7de2983292f2cab";
    
    //hash tree root of list of validators
    bytes32 validatorTreeRoot = 0x6229fa14e542826bc70666abe507defe4feb0a3ff2edb476eb3515147c27d889;
    bytes32[] beaconStateMerkleProof;
    bytes32[] validatorMerkleProof;
    bytes32[] validatorContainerFields;

    //hash tree root of individual validator container
    bytes32 validatorRoot = 0x6676e153ef747e73c622f8de0f04bdaecf8c2d343ec5277398a34b6c85e0f473;
    


    function initialize() internal {
        beaconStateMerkleProof.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        beaconStateMerkleProof.push(0x8a7c6aed738e0a0cf25ebb8c5b4da41173285b41451674890a0ca5a100c2d3c9);
        beaconStateMerkleProof.push(0xb4dbe880cd25d56a6866302afe567184b67006b2c022dd474d2eec3aa391c621);
        beaconStateMerkleProof.push(0x086ef90e3db0073ad2f8b2e6b38653d726e850fde26859dd881da1ac523598f0);
        beaconStateMerkleProof.push(0x1260718cd540a187a9dcff9f4d39116cdc1a0aed8a94fbe7a69fb87eae747be5);

        validatorContainerFields.push(0x5e2c2b702b0af22301f7ae52886da3827ea100b3d2a52222e6a10ea82e718a7f);
        validatorContainerFields.push(0x010000000000000000000000d5d575e71245442009ee208e8dcebfbcf958b8b6);
        validatorContainerFields.push(0x2000000000000000000000000000000000000000000000000000000000000000);
        validatorContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        validatorContainerFields.push(0x0200000000000000000000000000000000000000000000000000000000000000);
        validatorContainerFields.push(0x0300000000000000000000000000000000000000000000000000000000000000);
        validatorContainerFields.push(0x0600000000000000000000000000000000000000000000000000000000000000);
        validatorContainerFields.push(0x0900000000000000000000000000000000000000000000000000000000000000);

        validatorMerkleProof.push(0x0100000000000000000000000000000000000000000000000000000000000000);
    }

    function testDeployAndVerifyNewEigenPod(address podOwner, bytes memory signature, bytes32 depositDataRoot) public {
        initialize();
        bytes32 validatorIndex = bytes32(uint256(0));

        eigenPodManager.stake(pubkey, signature, depositDataRoot);

        bytes memory proofs = abi.encodePacked(validatorTreeRoot, beaconStateMerkleProof, validatorRoot, validatorIndex, validatorMerkleProof);
        emit log_named_bytes("Proofs", proofs);
        pod.verifyCorrectWithdrawalCredentials(pubkey, proofs, validatorContainerFields);
        

        
    }


}

