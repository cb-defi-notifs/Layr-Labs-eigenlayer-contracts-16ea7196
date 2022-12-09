// SPDX-License-Identifier: UNLICENCED

pragma solidity ^0.8.9;

import "./Merkle.sol";
import "./BytesLib.sol";
import "../libraries/Endian.sol";


//TODO: Validate this entire library

//Utility library for parsing and PHASE0 beacon chain block headers
//SSZ Spec: https://github.com/ethereum/consensus-specs/blob/dev/ssz/simple-serialize.md#merkleization
//BeaconBlockHeader Spec: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#beaconblockheader
//BeaconState Spec: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#beaconstate
library BeaconChainProofs{
    using BytesLib for bytes;
    // constants are the number of fields and the heights of the different merkle trees used in merkleizing beacon chain containers
    uint256 public constant NUM_BEACON_BLOCK_HEADER_FIELDS = 5;
    uint256 public constant BEACON_BLOCK_HEADER_FIELD_TREE_HEIGHT = 3;

    uint256 public constant NUM_BEACON_STATE_FIELDS = 21;
    uint256 public constant BEACON_STATE_FIELD_TREE_HEIGHT = 5;

    uint256 public constant NUM_ETH1_DATA_FIELDS = 3;
    uint256 public constant ETH1_DATA_FIELD_TREE_HEIGHT = 2;

    uint256 public constant NUM_VALIDATOR_FIELDS = 8;
    uint256 public constant VALIDATOR_FIELD_TREE_HEIGHT = 3;

    uint256 public constant NUM_EXECUTION_PAYLOAD_HEADER_FIELDS = 15;
    uint256 public constant EXECUTION_PAYLOAD_HEADER_FIELD_TREE_HEIGHT = 4;

    // HISTORICAL_ROOTS_LIMIT	 = 2**24, so tree height is 24
    uint256 public constant HISTORICAL_ROOTS_TREE_HEIGHT = 24;

    // SLOTS_PER_HISTORICAL_ROOT = 2**13, so tree height is 13
    uint public constant STATE_ROOTS_TREE_HEIGHT = 13;


    uint256 public constant NUM_WITHDRAWAL_FIELDS = 4;
    // tree height for hash tree of an individual withdrawal container
    uint256 public constant WITHDRAWAL_FIELD_TREE_HEIGHT = 2;

    uint256 public constant VALIDATOR_TREE_HEIGHT = 40;

    // the max withdrawals per payload is 2**4, making tree height = 4
    uint256 public constant WITHDRAWALS_TREE_HEIGHT = 4;

    // in beacon block header
    uint256 public constant STATE_ROOT_INDEX = 3;
    uint256 public constant PROPOSER_INDEX_INDEX = 1;
    // in beacon state
    uint256 public constant HISTORICAL_ROOTS_INDEX = 7;
    uint256 public constant ETH_1_ROOT_INDEX = 8;
    uint256 public constant VALIDATOR_TREE_ROOT_INDEX = 11;
    uint256 public constant WITHDRAWALS_ROOT_INDEX = 14;
    uint256 public constant EXECUTION_PAYLOAD_HEADER_INDEX = 24;
    // in validator
    uint256 public constant VALIDATOR_WITHDRAWAL_CREDENTIALS_INDEX = 1;
    uint256 public constant VALIDATOR_BALANCE_INDEX = 2;

    //In historicalBatch
    uint256 public constant HISTORICALBATCH_STATEROOTS_INDEX = 1;




    //TODO: Merklization can be optimized by supplying zero hashes. later on tho
    function computePhase0BeaconBlockHeaderRoot(bytes32[NUM_BEACON_BLOCK_HEADER_FIELDS] calldata blockHeaderFields) internal pure returns(bytes32) {
        bytes32[] memory paddedHeaderFields = new bytes32[](2**BEACON_BLOCK_HEADER_FIELD_TREE_HEIGHT);
        
        for (uint i = 0; i < NUM_BEACON_BLOCK_HEADER_FIELDS; i++) {
            paddedHeaderFields[i] = blockHeaderFields[i];
        }

        return Merkle.merkleizeSha256(paddedHeaderFields);
    }

    function computePhase0BeaconStateRoot(bytes32[NUM_BEACON_STATE_FIELDS] calldata beaconStateFields) internal pure returns(bytes32) {
        bytes32[] memory paddedBeaconStateFields = new bytes32[](2**BEACON_STATE_FIELD_TREE_HEIGHT);
        
        for (uint i = 0; i < NUM_BEACON_STATE_FIELDS; i++) {
            paddedBeaconStateFields[i] = beaconStateFields[i];
        }
        
        return Merkle.merkleizeSha256(paddedBeaconStateFields);
    }

    function computePhase0ValidatorRoot(bytes32[NUM_VALIDATOR_FIELDS] calldata validatorFields) internal pure returns(bytes32) {  
        bytes32[] memory paddedValidatorFields = new bytes32[](2**VALIDATOR_FIELD_TREE_HEIGHT);
        
        for (uint i = 0; i < NUM_VALIDATOR_FIELDS; i++) {
            paddedValidatorFields[i] = validatorFields[i];
        }

        return Merkle.merkleizeSha256(paddedValidatorFields);
    }

    function computePhase0Eth1DataRoot(bytes32[NUM_ETH1_DATA_FIELDS] calldata eth1DataFields) internal pure returns(bytes32) {  
        bytes32[] memory paddedEth1DataFields = new bytes32[](2**ETH1_DATA_FIELD_TREE_HEIGHT);
        
        for (uint i = 0; i < ETH1_DATA_FIELD_TREE_HEIGHT; i++) {
            paddedEth1DataFields[i] = eth1DataFields[i];
        }

        return Merkle.merkleizeSha256(paddedEth1DataFields);
    }

    /**
     * @notice This function verifies merkle proofs the fields of a certain validator against a beacon chain state root
     * @param beaconStateRoot is the beacon chain state root.
     * @param proofs is the data used in proving the validator's fields
     * @param validatorFields the claimed fields of the validator
     * @return validatorIndex the index of the proven validator
     */
    function verifyValidatorFields(
        bytes32 beaconStateRoot, 
        bytes calldata proofs, 
        bytes32[] calldata validatorFields
    ) internal view returns(uint64) {
        require(validatorFields.length == 2**VALIDATOR_FIELD_TREE_HEIGHT, "EigenPod.verifyValidatorFields: Validator fields has incorrect length");
        uint256 pointer;
        bool valid;
        //verify that the validatorTreeRoot is within the top level beacon state tree
        bytes32 validatorTreeRoot = proofs.toBytes32(0);

        //offset 32 bytes for validatorTreeRoot
        pointer += 32;
        valid = Merkle.verifyInclusionSha256(
            proofs.slice(pointer, 32 * BeaconChainProofs.BEACON_STATE_FIELD_TREE_HEIGHT),
            beaconStateRoot,
            validatorTreeRoot,
            BeaconChainProofs.VALIDATOR_TREE_ROOT_INDEX
        );
        require(valid, "EigenPod.verifyValidatorFields: Invalid validator tree root from beacon state proof");
        //offset the length of the beacon state proof
        pointer += 32 * BeaconChainProofs.BEACON_STATE_FIELD_TREE_HEIGHT;
        // verify the proof of the validator metadata root against the merkle root of the entire validator tree
        //https://github.com/prysmaticlabs/prysm/blob/de8e50d8b6bcca923c38418e80291ca4c329848b/beacon-chain/state/stateutil/validator_root.go#L26
        bytes32 validatorRoot = proofs.toBytes32(pointer);
        //make sure that the provided validatorFields are consistent with the proven leaf
        require(validatorRoot == Merkle.merkleizeSha256(validatorFields), "EigenPod.verifyValidatorFields: Invalid validator fields");
        //offset another 32 bytes for the length of the validatorRoot
        pointer += 32;
        //verify that the validatorRoot is within the validator tree
        valid = Merkle.verifyInclusionSha256(
            /**
            * plus 1 here is because the actual validator merkle tree involves hashing 
            * the final root with the lenght of the list, adding a level to the tree
            */
            proofs.slice(pointer + 32, 32 * (BeaconChainProofs.VALIDATOR_TREE_HEIGHT + 1)),
            validatorTreeRoot,
            validatorRoot,
            proofs.toUint256(pointer)
        );
        require(valid, "EigenPod.verifyValidatorFields: Invalid validator root from validator tree root proof");
        return uint64(proofs.toUint256(pointer));
    }

    /// @param beaconStateRoot is the latest beaconStateRoot posted by the oracle
    function verifyWithdrawalProofs(
        bytes32 beaconStateRoot, 
        bytes calldata proofs, 
        bytes32[] calldata withdrawalFields
    ) internal view {
        require(withdrawalFields.length == BeaconChainProofs.NUM_WITHDRAWAL_FIELDS, "incorrect executionPayloadHeaderFields length");
        uint256 pointer = 0;
        bool valid;

        //check that beacon state root from oracle is present in historical roots
        pointer = verifyBeaconChainRootProof(beaconStateRoot, proofs, pointer);


        bytes32 executionPayloadHeaderRoot = proofs.toBytes32(0);
        pointer += 32;
        //verify that execution payload header root is correct against beacon state root
        valid = Merkle.verifyInclusionSha256(
            proofs.slice(pointer, 32 * BeaconChainProofs.BEACON_STATE_FIELD_TREE_HEIGHT), 
            beaconStateRoot, 
            executionPayloadHeaderRoot, 
            BeaconChainProofs.EXECUTION_PAYLOAD_HEADER_INDEX
        );
        require(valid, "Invalid execution payload header proof");

        pointer += 32 * BeaconChainProofs.BEACON_STATE_FIELD_TREE_HEIGHT;
        bytes32 withdrawalsRoot = proofs.toBytes32(pointer);
        pointer +=32;

        //verify that the withdrawals root is correct against the execution payload header root
        valid = Merkle.verifyInclusionSha256(
            proofs.slice(pointer, 32 * BeaconChainProofs.EXECUTION_PAYLOAD_HEADER_FIELD_TREE_HEIGHT), 
            executionPayloadHeaderRoot, 
            withdrawalsRoot, 
            BeaconChainProofs.WITHDRAWALS_ROOT_INDEX
        );
        require(valid, "Invalid withdrawals root proof");

        pointer += 32 * BeaconChainProofs.EXECUTION_PAYLOAD_HEADER_FIELD_TREE_HEIGHT;
        bytes32 individualWithdrawalContainerRoot = proofs.toBytes32(pointer);
        pointer += 32;

        require(individualWithdrawalContainerRoot == Merkle.merkleizeSha256(withdrawalFields), "provided withdrawalFields do not match withdrawalContainerRoot");

        valid = Merkle.verifyInclusionSha256(
            proofs.slice(pointer + 32, 32 * BeaconChainProofs.WITHDRAWALS_TREE_HEIGHT),
            withdrawalsRoot,
            individualWithdrawalContainerRoot,
            proofs.toUint256(pointer)
        );
        require(valid, "invalid withdrawal container inclusion proof");
    }

    function verifyBeaconChainRootProof(
        bytes32 beaconStateRoot, 
        bytes calldata proofs,
        uint256 pointer
    )internal view returns(uint256){

        bytes32 historicalRootsRoot = proofs.toBytes32(pointer);
        pointer += 32;
        //check if the historical_roots array's root is in the beacon state
        bool valid = Merkle.verifyInclusionSha256(
            proofs.slice(pointer, 32 * BeaconChainProofs.BEACON_STATE_FIELD_TREE_HEIGHT), 
            beaconStateRoot, 
            historicalRootsRoot, 
            BeaconChainProofs.HISTORICAL_ROOTS_INDEX
        );
        require(valid, "stateroots Root proof invalid");
        pointer += 32 * BeaconChainProofs.BEACON_STATE_FIELD_TREE_HEIGHT;



        bytes32 historicalBatchRoot = proofs.toBytes32(pointer);
        pointer += 32;
        // check if the historicalBatch's root is in the historical_roots array
        valid = Merkle.verifyInclusionSha256(
            proofs.slice(pointer + 32, 32 * BeaconChainProofs.HISTORICAL_ROOTS_TREE_HEIGHT), 
            historicalRootsRoot, 
            historicalBatchRoot, 
            proofs.toUint256(pointer)
        );
        require(valid, "historicalBatchRoot proof invalid");
        pointer += 32 + 32 * BeaconChainProofs.HISTORICAL_ROOTS_TREE_HEIGHT;



        bytes32 stateRootsRoot = proofs.toBytes32(pointer);
        pointer += 32;
        //now we check that the stateRoots array's root is included in the HistoricalBatch
        valid = Merkle.verifyInclusionSha256(
            proofs.slice(pointer, 32), //the proof is only checking that hash(blockRootsRoot, stateRootsRoot) = historicalBatchRoot
            historicalBatchRoot, 
            stateRootsRoot, 
            BeaconChainProofs.HISTORICALBATCH_STATEROOTS_INDEX
        );
        require(valid, "staterootsRoot proof is invalid");
        pointer += 32 * BeaconChainProofs.HISTORICAL_ROOTS_TREE_HEIGHT;

    

        bytes32 beaconStateRootToVerify = proofs.toBytes32(pointer);
        pointer += 32;
        valid = Merkle.verifyInclusionSha256(
            proofs.slice(pointer + 32, 32 * BeaconChainProofs.STATE_ROOTS_TREE_HEIGHT), 
            stateRootsRoot, 
            beaconStateRootToVerify, 
            proofs.toUint256(pointer)
        );
        require(valid, "beaconstateRoot to verify proof is invalid");
        pointer += 32 + 32 * BeaconChainProofs.STATE_ROOTS_TREE_HEIGHT;

        return pointer;
    }
}