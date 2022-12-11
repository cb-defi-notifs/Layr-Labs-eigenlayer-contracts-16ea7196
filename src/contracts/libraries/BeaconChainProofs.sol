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
    uint256 internal constant NUM_BEACON_BLOCK_HEADER_FIELDS = 5;
    uint256 internal constant BEACON_BLOCK_HEADER_FIELD_TREE_HEIGHT = 3;

    uint256 internal constant NUM_BEACON_STATE_FIELDS = 21;
    uint256 internal constant BEACON_STATE_FIELD_TREE_HEIGHT = 5;

    uint256 internal constant NUM_ETH1_DATA_FIELDS = 3;
    uint256 internal constant ETH1_DATA_FIELD_TREE_HEIGHT = 2;

    uint256 internal constant NUM_VALIDATOR_FIELDS = 8;
    uint256 internal constant VALIDATOR_FIELD_TREE_HEIGHT = 3;

    uint256 internal constant NUM_EXECUTION_PAYLOAD_HEADER_FIELDS = 15;
    uint256 internal constant EXECUTION_PAYLOAD_HEADER_FIELD_TREE_HEIGHT = 4;

    // HISTORICAL_ROOTS_LIMIT	 = 2**24, so tree height is 24
    uint256 internal constant HISTORICAL_ROOTS_TREE_HEIGHT = 24;

    // HISTORICAL_BATCH is root of state_roots and block_root, so number of leaves =  2^1
    uint256 internal constant HISTORICAL_BATCH_TREE_HEIGHT = 1;

    // SLOTS_PER_HISTORICAL_ROOT = 2**13, so tree height is 13
    uint256 internal constant STATE_ROOTS_TREE_HEIGHT = 13;


    uint256 internal constant NUM_WITHDRAWAL_FIELDS = 4;
    // tree height for hash tree of an individual withdrawal container
    uint256 internal constant WITHDRAWAL_FIELD_TREE_HEIGHT = 2;

    uint256 internal constant VALIDATOR_TREE_HEIGHT = 40;

    // MAX_WITHDRAWALS_PER_PAYLOAD = 2**4, making tree height = 4
    uint256 internal constant WITHDRAWALS_TREE_HEIGHT = 4;


    // in beacon block header
    uint256 internal constant STATE_ROOT_INDEX = 3;
    uint256 internal constant PROPOSER_INDEX_INDEX = 1;
    // in beacon state
    uint256 internal constant STATE_ROOTS_INDEX = 6;
    uint256 internal constant HISTORICAL_ROOTS_INDEX = 7;
    uint256 internal constant ETH_1_ROOT_INDEX = 8;
    uint256 internal constant VALIDATOR_TREE_ROOT_INDEX = 11;
    uint256 internal constant EXECUTION_PAYLOAD_HEADER_INDEX = 24;
    uint256 internal constant HISTORICAL_BATCH_STATE_ROOT_INDEX = 1;

    // in validator
    uint256 internal constant VALIDATOR_WITHDRAWAL_CREDENTIALS_INDEX = 1;
    uint256 internal constant VALIDATOR_BALANCE_INDEX = 2;
    
    // in exection payload header
    uint256 internal constant BLOCK_NUMBER_INDEX = 6;
    uint256 internal constant WITHDRAWALS_ROOT_INDEX = 14;

    // in withdrawal
    uint256 internal constant WITHDRAWAL_VALIDATOR_INDEX_INDEX = 1;
    uint256 internal constant WITHDRAWAL_VALIDATOR_AMOUNT_INDEX = 3;

    //In historicalBatch
    uint256 internal constant HISTORICALBATCH_STATEROOTS_INDEX = 1;

    struct WithdrawalAndBlockNumberProof {
        uint16 stateRootIndex;
        bytes32 executionPayloadHeaderRoot;
        bytes executionPayloadHeaderProof;
        uint8 withdrawalIndex;
        bytes withdrawalProof;
        bytes blockNumberProof;
    }


    //TODO: Merklization can be optimized by supplying zero hashes. later on tho
    function computePhase0BeaconBlockHeaderRoot(bytes32[NUM_BEACON_BLOCK_HEADER_FIELDS] calldata blockHeaderFields) internal pure returns(bytes32) {
        bytes32[] memory paddedHeaderFields = new bytes32[](2**BEACON_BLOCK_HEADER_FIELD_TREE_HEIGHT);
        
        for (uint256 i = 0; i < NUM_BEACON_BLOCK_HEADER_FIELDS; ++i) {
            paddedHeaderFields[i] = blockHeaderFields[i];
        }

        return Merkle.merkleizeSha256(paddedHeaderFields);
    }

    function computePhase0BeaconStateRoot(bytes32[NUM_BEACON_STATE_FIELDS] calldata beaconStateFields) internal pure returns(bytes32) {
        bytes32[] memory paddedBeaconStateFields = new bytes32[](2**BEACON_STATE_FIELD_TREE_HEIGHT);
        
        for (uint256 i = 0; i < NUM_BEACON_STATE_FIELDS; ++i) {
            paddedBeaconStateFields[i] = beaconStateFields[i];
        }
        
        return Merkle.merkleizeSha256(paddedBeaconStateFields);
    }

    function computePhase0ValidatorRoot(bytes32[NUM_VALIDATOR_FIELDS] calldata validatorFields) internal pure returns(bytes32) {  
        bytes32[] memory paddedValidatorFields = new bytes32[](2**VALIDATOR_FIELD_TREE_HEIGHT);
        
        for (uint256 i = 0; i < NUM_VALIDATOR_FIELDS; ++i) {
            paddedValidatorFields[i] = validatorFields[i];
        }

        return Merkle.merkleizeSha256(paddedValidatorFields);
    }

    function computePhase0Eth1DataRoot(bytes32[NUM_ETH1_DATA_FIELDS] calldata eth1DataFields) internal pure returns(bytes32) {  
        bytes32[] memory paddedEth1DataFields = new bytes32[](2**ETH1_DATA_FIELD_TREE_HEIGHT);
        
        for (uint256 i = 0; i < ETH1_DATA_FIELD_TREE_HEIGHT; ++i) {
            paddedEth1DataFields[i] = eth1DataFields[i];
        }

        return Merkle.merkleizeSha256(paddedEth1DataFields);
    }

    /**
     * @notice This function verifies merkle proofs the fields of a certain validator against a beacon chain state root
     * @param validatorIndex the index of the proven validator
     * @param beaconStateRoot is the beacon chain state root.
     * @param proof is the data used in proving the validator's fields
     * @param validatorFields the claimed fields of the validator
     */
    function verifyValidatorFields(
        uint40 validatorIndex,
        bytes32 beaconStateRoot,
        bytes calldata proof, 
        bytes32[] calldata validatorFields
    ) internal view {
        
        require(validatorFields.length == 2**VALIDATOR_FIELD_TREE_HEIGHT, "BeaconChainProofs.verifyValidatorFields: Validator fields has incorrect length");

        /**
         * Note: the length of the validator merkle proof is BeaconChainProofs.VALIDATOR_TREE_HEIGHT + 1.
         * There is an additional layer added by hashing the root with the length of the validator list
         */
        require(proof.length == 32 * ((VALIDATOR_TREE_HEIGHT + 1) + BEACON_STATE_FIELD_TREE_HEIGHT), "BeaconChainProofs.verifyValidatorFields: Proof has incorrect length");
        uint256 index = (VALIDATOR_TREE_ROOT_INDEX << (VALIDATOR_TREE_HEIGHT + 1)) | uint256(validatorIndex);
        // merkleize the validatorFields to get the leaf to prove
        bytes32 validatorRoot = Merkle.merkleizeSha256(validatorFields);

        // verify the proof
        require(Merkle.verifyInclusionSha256(proof, beaconStateRoot, validatorRoot, index), "BeaconChainProofs.verifyValidatorFields: Invalid merkle proof");
    }

    /// @param beaconStateRoot is the latest beaconStateRoot posted by the oracle
    function verifyWithdrawalFieldsAndBlockNumber(
        bytes32 beaconStateRoot,
        WithdrawalAndBlockNumberProof calldata proof,
        bytes32 blockNumberRoot,
        bytes32[] calldata withdrawalFields
    ) internal view {
        require(proof.stateRootIndex < 2**STATE_ROOTS_TREE_HEIGHT, "BeaconChainProofs.verifyWithdrawalFields: stateRootIndex is too large");
        require(proof.withdrawalIndex < 2**WITHDRAWALS_TREE_HEIGHT, "BeaconChainProofs.verifyWithdrawalFields: withdrawalIndex is too large");
        require(withdrawalFields.length == 2**WITHDRAWAL_FIELD_TREE_HEIGHT, "BeaconChainProofs.verifyWithdrawalFields: withdrawalFields has incorrect length");

        // verify the executionPayloadHeaderProof first
        require(
            proof.executionPayloadHeaderProof.length == 32 * (
                BEACON_STATE_FIELD_TREE_HEIGHT + STATE_ROOTS_TREE_HEIGHT + BEACON_STATE_FIELD_TREE_HEIGHT
            ), 
            "BeaconChainProofs.verifyWithdrawalFields: executionPayloadHeaderProof length is incorrect"
        );


        uint256 index = 
            (STATE_ROOTS_INDEX << (STATE_ROOTS_TREE_HEIGHT + BEACON_STATE_FIELD_TREE_HEIGHT)) 
            | (uint256(proof.stateRootIndex) << BEACON_STATE_FIELD_TREE_HEIGHT) 
            | EXECUTION_PAYLOAD_HEADER_INDEX;

        
        require(
            Merkle.verifyInclusionSha256(proof.executionPayloadHeaderProof, beaconStateRoot, proof.executionPayloadHeaderRoot, index), 
            "BeaconChainProofs.verifyWithdrawalFields: executionPayloadHeader merkle inclusion proof failed"
        );

        // verify the blockNumber proof second
        require(
            proof.blockNumberProof.length == 32 * EXECUTION_PAYLOAD_HEADER_FIELD_TREE_HEIGHT, 
            "BeaconChainProofs.verifyWithdrawalFields: blockNumberProof length is incorrect"
        );

        require(
            Merkle.verifyInclusionSha256(proof.blockNumberProof, proof.executionPayloadHeaderRoot, blockNumberRoot, BLOCK_NUMBER_INDEX), 
            "BeaconChainProofs.verifyWithdrawalFields: blockNumber merkle inclusion proof failed"
        );


        // Note: WITHDRAWALS_TREE_HEIGHT + 1 accounts for the hashing of the withdrawal list root with the number of withdrawals in the withdrawal list
        require(
            proof.withdrawalProof.length == 32 * (
                EXECUTION_PAYLOAD_HEADER_FIELD_TREE_HEIGHT + WITHDRAWALS_TREE_HEIGHT + 1
            ), "BeaconChainProofs.verifyWithdrawalFields: withdrawalProof length is incorrect");


        index = (WITHDRAWALS_ROOT_INDEX << (WITHDRAWALS_TREE_HEIGHT + 1)) | proof.withdrawalIndex;

        require(
            Merkle.verifyInclusionSha256(proof.withdrawalProof, proof.executionPayloadHeaderRoot,  Merkle.merkleizeSha256(withdrawalFields), index), 
            "BeaconChainProofs.verifyWithdrawalFields: Withdrawal merkle inclusion proof failed"
        );
    }

}