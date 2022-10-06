// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../libraries/BeaconChainProofs.sol";
import "../libraries/BytesLib.sol";
import "../interfaces/IETHPOSDeposit.sol";
import "../interfaces/IEigenPod.sol";

contract EigenPod is IEigenPod {
    using BytesLib for bytes;

    enum VALIDATOR_STATUS {
        INACTIVE, //doesnt exist
        INITIALIZED, //staked on ethpos but withdrawal credentials not proven
        ACTIVE //staked on ethpos and withdrawal credentials are pointed
    }

    //TODO: change this to constant in prod
    IETHPOSDeposit immutable ethPOS;

    mapping(bytes32 => VALIDATOR_STATUS) public validatorStauses;

    constructor(IETHPOSDeposit _ethPOS) {
        ethPOS = _ethPOS;
    }


    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable {
        // get pubKeyHash
        bytes32 pubkeyHash = keccak256(abi.encodePacked(pubkey));
        // stake on ethPOS
        ethPOS.deposit{value : msg.value}(pubkey, podWithdrawalCredentials(), signature, depositDataRoot);
        //if not previously known validator, then update status
        if(validatorStauses[pubkeyHash] == VALIDATOR_STATUS.INACTIVE) {
            validatorStauses[pubkeyHash] = VALIDATOR_STATUS.INITIALIZED;
        }
    }

    function proveCorrectWithdrawalCredentials(bytes calldata pubkey, bytes32 beaconStateRoot, bytes calldata proofs) external {
        //TODO: verify the beaconStateRoot is consistent with oracle

        // get pubKeyHash
        bytes32 pubkeyHash = keccak256(abi.encodePacked(pubkey));
        require(validatorStauses[pubkeyHash] == VALIDATOR_STATUS.INITIALIZED, "EigenPod.proveCorrectWithdrawalCredentials: Validator not initialized");
        
        bytes32 validatorTreeRoot = proofs.toBytes32(0);
        //offset 32 bytes for validatorTreeRoot
        uint256 pointer = 32;
        //verify that the validatorTreeRoot is within the top level beacon state tree
        bool valid = Merkle.checkMembershipSha256(
            validatorTreeRoot,
            BeaconChainProofs.VALIDATOR_TREE_ROOT_INDEX,
            beaconStateRoot,
            proofs.slice(pointer, 32 * BeaconChainProofs.NUM_BEACON_STATE_FIELDS)
        );
        require(valid, "EigenPod.proveCorrectWithdrawalCredentials: Invalid validator tree root from beacon state proof");
        //offset the length of the beacon state proof
        pointer += 32 * BeaconChainProofs.NUM_BEACON_STATE_FIELDS;
        uint32 validatorIndex = proofs.toUint32(pointer);
        //offset another 4 bytes for the length of the validatorIndex
        pointer += 4;
        //verify that the validatorRoot is within the validator tree
        valid = Merkle.checkMembershipSha256(
            validatorTreeRoot,
            uint256(validatorIndex),
            validatorTreeRoot,
            proofs.slice(pointer, 32 * BeaconChainProofs.VALIDATOR_TREE_HEIGHT)
        );
        require(valid, "EigenPod.proveCorrectWithdrawalCredentials: Invalid validator root from validator tree root proof");

        //todo: finish this proof
    }

    function podWithdrawalCredentials() internal view returns(bytes memory) {
        return abi.encodePacked(bytes1(uint8(1)), bytes11(0), address(this));
    }

}