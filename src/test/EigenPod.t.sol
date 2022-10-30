//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./TestHelper.t.sol";
import "../contracts/interfaces/IEigenPod.sol";


contract EigenPodTests is TestHelper {

    bytes pubkey = hex"88347ed1c492eedc97fc8c506a35d44d81f27a0c7a1c661b35913cfd15256c0cccbd34a83341f505c7de2983292f2cab";
    
    //hash tree root of list of validators
    bytes32 validatorTreeRoot = 0x0b64203cde1de24375510cd8242e020e8810b811c1ec1850d2a322221126ee67;
    bytes[] beaconStateMerkleProof;
    bytes32[] validatorContainerFields;

    //hash tree root of individual validator container
    bytes32 validatorRoot = 0xaf25274e74d8d4a4134ea714699b27240a963095eba7183f793bb09fa25df231;
    

    function initialize() internal {
        beaconStateMerkleProof.push(hex"0000000000000000000000000000000000000000000000000000000000000000");
        beaconStateMerkleProof.push(hex"8a7c6aed738e0a0cf25ebb8c5b4da41173285b41451674890a0ca5a100c2d3c9");
        beaconStateMerkleProof.push(hex"b4dbe880cd25d56a6866302afe567184b67006b2c022dd474d2eec3aa391c621");
        beaconStateMerkleProof.push(hex"086ef90e3db0073ad2f8b2e6b38653d726e850fde26859dd881da1ac523598f0");
        beaconStateMerkleProof.push(hex"1260718cd540a187a9dcff9f4d39116cdc1a0aed8a94fbe7a69fb87eae747be5");

        validatorContainerFields.push(0x5e2c2b702b0af22301f7ae52886da3827ea100b3d2a52222e6a10ea82e718a7f);
        validatorContainerFields.push(0x88347ed188347ed188347ed188347ed188347ed188347ed188347ed188347ed1);
        validatorContainerFields.push(0x2000000000000000000000000000000000000000000000000000000000000000);
        validatorContainerFields.push(0x0000000000000000000000000000000000000000000000000000000000000000);
        validatorContainerFields.push(0x0200000000000000000000000000000000000000000000000000000000000000);
        validatorContainerFields.push(0x0300000000000000000000000000000000000000000000000000000000000000);
        validatorContainerFields.push(0x0600000000000000000000000000000000000000000000000000000000000000);
        validatorContainerFields.push(0x0900000000000000000000000000000000000000000000000000000000000000);
       
    }

    function testDeployNewEigenPod(address podOwner, bytes memory signature, bytes32 depositDataRoot) public {
        initialize();

        cheats.startPrank(podOwner);
        eigenPodManager.stake(pubkey, signature, depositDataRoot);
        cheats.stopPrank();

        IEigenPod pod = eigenPodManager.getPod(podOwner);

        bytes memory proofs = abi.encode(validatorTreeRoot, beaconStateMerkleProof, validatorRoot);


        pod.verifyCorrectWithdrawalCredentials(pubkey, proofs, validatorContainerFields);
        

        
    }


}

