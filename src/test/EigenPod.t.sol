//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./TestHelper.t.sol";
import "../contracts/interfaces/IEigenPod.sol";
import "./utils/BeaconChainUtils.sol";


contract EigenPodTests is TestHelper, BeaconChainProofUtils {
    using BytesLib for bytes;

    bytes pubkey = hex"88347ed1c492eedc97fc8c506a35d44d81f27a0c7a1c661b35913cfd15256c0cccbd34a83341f505c7de2983292f2cab";
    
    //hash tree root of list of validators
    bytes32 validatorTreeRoot;

    //hash tree root of individual validator container
    bytes32 validatorRoot;

    address podOwner = address(42000094993494);

    function testDeployAndVerifyNewEigenPod(bytes memory signature, bytes32 depositDataRoot) public {
        (beaconStateMerkleProof, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getInitialDepositProof();

        cheats.startPrank(podOwner);
        eigenPodManager.stake(pubkey, signature, depositDataRoot);
        cheats.stopPrank();

        IEigenPod newPod;

        newPod = eigenPodManager.getPod(podOwner);

        bytes32 validatorIndex = bytes32(uint256(0));
        bytes memory proofs = abi.encodePacked(validatorTreeRoot, beaconStateMerkleProof, validatorRoot, validatorIndex, validatorMerkleProof);
        newPod.verifyCorrectWithdrawalCredentials(pubkey, proofs, validatorContainerFields);

        uint64 validatorBalance = Endian.fromLittleEndianUint64(validatorContainerFields[2]);
        require(eigenPodManager.getBalance(podOwner) == validatorBalance, "Validator balance not updated correctly");

        IInvestmentStrategy beaconChainETHStrategy = investmentManager.beaconChainETHStrategy();
        uint256 beaconChainETHShares = investmentManager.investorStratShares(podOwner, beaconChainETHStrategy);

        require(beaconChainETHShares == validatorBalance, "investmentManager shares not updated correctly");
    }

    function testUpdateSlashedBeaconBalance(bytes memory signature, bytes32 depositDataRoot) public {
        //make initial deposit
        testDeployAndVerifyNewEigenPod(signature, depositDataRoot);

        //get updated proof, set beaconchain state root
        (beaconStateMerkleProof, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getSlashedDepositProof();
        beaconChainOracle.setBeaconChainStateRoot(0xddbf7dfbb5c63a27509fa76e172cc7f556a9a702b5d1db5d7b118fc006ea78e8);

        IEigenPod eigenPod;
        eigenPod = eigenPodManager.getPod(podOwner);
        
        bytes32 validatorIndex = bytes32(uint256(0));
        bytes memory proofs = abi.encodePacked(validatorTreeRoot, beaconStateMerkleProof, validatorRoot, validatorIndex, validatorMerkleProof);
        eigenPod.verifyBalanceUpdate(pubkey, proofs, validatorContainerFields);
        
        uint64 validatorBalance = Endian.fromLittleEndianUint64(validatorContainerFields[2]);
        require(eigenPodManager.getBalance(podOwner) == validatorBalance, "Validator balance not updated correctly");
        require(investmentManager.slasher().isFrozen(podOwner), "podOwner not frozen successfully");

    }

    function testDeployNewEigenPodWithWrongPubkey(bytes memory wrongPubkey, bytes memory signature, bytes32 depositDataRoot) public {
        (beaconStateMerkleProof, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getInitialDepositProof();

        cheats.startPrank(podOwner);
        eigenPodManager.stake(wrongPubkey, signature, depositDataRoot);
        cheats.stopPrank();

        IEigenPod newPod;
        newPod = eigenPodManager.getPod(podOwner);

        bytes32 validatorIndex = bytes32(uint256(0));
        bytes memory proofs = abi.encodePacked(validatorTreeRoot, beaconStateMerkleProof, validatorRoot, validatorIndex, validatorMerkleProof);
        cheats.expectRevert(bytes("EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for provided pubkey"));
        newPod.verifyCorrectWithdrawalCredentials(wrongPubkey, proofs, validatorContainerFields);
    }

    function testDeployNewEigenPodWithWrongWithdrawalCreds(address wrongWithdrawalAddress, bytes memory signature, bytes32 depositDataRoot) public {
        (beaconStateMerkleProof, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getInitialDepositProof();

        cheats.startPrank(podOwner);
        eigenPodManager.stake(pubkey, signature, depositDataRoot);
        cheats.stopPrank();

        IEigenPod newPod;
        newPod = eigenPodManager.getPod(podOwner);
        validatorContainerFields[1] = abi.encodePacked(bytes1(uint8(1)), bytes11(0), wrongWithdrawalAddress).toBytes32(0);

        bytes32 validatorIndex = bytes32(uint256(0));
        bytes memory proofs = abi.encodePacked(validatorTreeRoot, beaconStateMerkleProof, validatorRoot, validatorIndex, validatorMerkleProof);
        cheats.expectRevert(bytes("EigenPod.verifyValidatorFields: Invalid validator fields"));
        newPod.verifyCorrectWithdrawalCredentials(pubkey, proofs, validatorContainerFields);
    }

    function testDeployNewEigenPodWithActiveValidator(bytes memory signature, bytes32 depositDataRoot) public {
        (beaconStateMerkleProof, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getInitialDepositProof();
        

        cheats.startPrank(podOwner);
        eigenPodManager.stake(pubkey, signature, depositDataRoot);
        cheats.stopPrank();

        IEigenPod newPod;
        newPod = eigenPodManager.getPod(podOwner);

        bytes32 validatorIndex = bytes32(uint256(0));
        bytes memory proofs = abi.encodePacked(validatorTreeRoot, beaconStateMerkleProof, validatorRoot, validatorIndex, validatorMerkleProof);
        newPod.verifyCorrectWithdrawalCredentials(pubkey, proofs, validatorContainerFields);

        cheats.expectRevert(bytes("EigenPod.verifyCorrectWithdrawalCredentials: Validator not inactive"));
        newPod.verifyCorrectWithdrawalCredentials(pubkey, proofs, validatorContainerFields);
    }

    function testWithdrawal(bytes memory signature, bytes32 depositDataRoot) public {
        //make initial deposit
        testDeployAndVerifyNewEigenPod(signature, depositDataRoot);

        uint128 balance = eigenPodManager.getBalance(podOwner);

         IEigenPod newPod;
        newPod = eigenPodManager.getPod(podOwner);
        newPod.topUpPodBalance{value : balance*(1**18)}();



        //eigenPodManager.withdrawBeaconChainETH(podOwner, address(this), balance);

    



        

    } 


}

