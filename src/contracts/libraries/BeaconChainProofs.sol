// SPDX-License-Identifier: UNLICENCED

pragma solidity =0.8.12;

import "./Merkle.sol";
import "./BytesLib.sol";
import "../libraries/Endian.sol";

//Utility library for parsing and PHASE0 beacon chain block headers
//SSZ Spec: https://github.com/ethereum/consensus-specs/blob/dev/ssz/simple-serialize.md#merkleization
//BeaconBlockHeader Spec: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#beaconblockheader
//BeaconState Spec: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#beaconstate
library BeaconChainProofs {
    using BytesLib for bytes;
    // constants are the number of fields and the heights of the different merkle trees used in merkleizing beacon chain containers
    uint256 internal constant NUM_BEACON_BLOCK_HEADER_FIELDS = 5;
    uint256 internal constant BEACON_BLOCK_HEADER_FIELD_TREE_HEIGHT = 3;

    uint256 internal constant NUM_BEACON_BLOCK_BODY_FIELDS = 11;
    uint256 internal constant BEACON_BLOCK_BODY_FIELD_TREE_HEIGHT = 4;

    uint256 internal constant NUM_BEACON_STATE_FIELDS = 21;
    uint256 internal constant BEACON_STATE_FIELD_TREE_HEIGHT = 5;

    uint256 internal constant NUM_ETH1_DATA_FIELDS = 3;
    uint256 internal constant ETH1_DATA_FIELD_TREE_HEIGHT = 2;

    uint256 internal constant NUM_VALIDATOR_FIELDS = 8;
    uint256 internal constant VALIDATOR_FIELD_TREE_HEIGHT = 3;

    uint256 internal constant NUM_EXECUTION_PAYLOAD_HEADER_FIELDS = 15;
    uint256 internal constant EXECUTION_PAYLOAD_HEADER_FIELD_TREE_HEIGHT = 4;


    uint256 internal constant NUM_EXECUTION_PAYLOAD_FIELDS = 15;
    uint256 internal constant EXECUTION_PAYLOAD_FIELD_TREE_HEIGHT = 4;


    // HISTORICAL_ROOTS_LIMIT	 = 2**24, so tree height is 24
    uint256 internal constant HISTORICAL_ROOTS_TREE_HEIGHT = 24;

    // HISTORICAL_BATCH is root of state_roots and block_root, so number of leaves =  2^1
    uint256 internal constant HISTORICAL_BATCH_TREE_HEIGHT = 1;

    // SLOTS_PER_HISTORICAL_ROOT = 2**13, so tree height is 13
    uint256 internal constant STATE_ROOTS_TREE_HEIGHT = 13;
    uint256 internal constant BLOCK_ROOTS_TREE_HEIGHT = 13;


    uint256 internal constant NUM_WITHDRAWAL_FIELDS = 4;
    // tree height for hash tree of an individual withdrawal container
    uint256 internal constant WITHDRAWAL_FIELD_TREE_HEIGHT = 2;

    uint256 internal constant VALIDATOR_TREE_HEIGHT = 40;

    // MAX_WITHDRAWALS_PER_PAYLOAD = 2**4, making tree height = 4
    uint256 internal constant WITHDRAWALS_TREE_HEIGHT = 4;

    //in beacon block body
    uint256 internal constant EXECUTION_PAYLOAD_INDEX = 9;

    // in beacon block header
    uint256 internal constant STATE_ROOT_INDEX = 3;
    uint256 internal constant PROPOSER_INDEX_INDEX = 1;
    uint256 internal constant SLOT_INDEX = 0;
    uint256 internal constant BODY_ROOT_INDEX = 4;
    // in beacon state
    uint256 internal constant STATE_ROOTS_INDEX = 6;
    uint256 internal constant BLOCK_ROOTS_INDEX = 5;
    uint256 internal constant HISTORICAL_ROOTS_INDEX = 7;
    uint256 internal constant ETH_1_ROOT_INDEX = 8;
    uint256 internal constant VALIDATOR_TREE_ROOT_INDEX = 11;
    uint256 internal constant EXECUTION_PAYLOAD_HEADER_INDEX = 24;
    uint256 internal constant HISTORICAL_BATCH_STATE_ROOT_INDEX = 1;

    // in validator
    uint256 internal constant VALIDATOR_WITHDRAWAL_CREDENTIALS_INDEX = 1;
    uint256 internal constant VALIDATOR_BALANCE_INDEX = 2;
    uint256 internal constant VALIDATOR_WITHDRAWABLE_EPOCH_INDEX = 7;
    
    // in exection payload header
    uint256 internal constant BLOCK_NUMBER_INDEX = 6;
    uint256 internal constant WITHDRAWALS_ROOT_INDEX = 14;

    //in execution payload
    uint256 internal constant WITHDRAWALS_INDEX = 14;

    // in withdrawal
    uint256 internal constant WITHDRAWAL_VALIDATOR_INDEX_INDEX = 1;
    uint256 internal constant WITHDRAWAL_VALIDATOR_AMOUNT_INDEX = 3;

    //In historicalBatch
    uint256 internal constant HISTORICALBATCH_STATEROOTS_INDEX = 1;

    //Misc Constants
    uint256 internal constant SLOTS_PER_EPOCH = 32;

    struct WithdrawalAndBlockNumberProof {
        uint16 stateRootIndex;
        bytes32 executionPayloadHeaderRoot;
        bytes executionPayloadHeaderProof;
        uint8 withdrawalIndex;
        bytes withdrawalProof;
        bytes blockNumberProof;
    }

    struct WithdrawalProofs {
        bytes blockHeaderProof;
        bytes withdrawalProof;
        bytes slotProof;
        bytes validatorProof;
        bytes executionPayloadProof;
        bytes blockNumberProof;
        uint16 blockHeaderRootIndex;
        uint8 withdrawalIndex;
        uint8 validatorIndex;
        bytes32 blockHeaderRoot;
        bytes32 blockBodyRoot;
        bytes32 slotRoot;
        bytes32 blockNumberRoot;
        bytes32 executionPayloadRoot;
    }


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

    function verifySlotAndWithdrawalFields(
        bytes32 beaconStateRoot,
        WithdrawalProofs calldata proofs,
        bytes32[] calldata withdrawalFields,
        bytes32[] calldata validatorFields
    ) internal view {
        require(withdrawalFields.length == 2**WITHDRAWAL_FIELD_TREE_HEIGHT, "BeaconChainProofs.verifySlotAndWithdrawalFields: withdrawalFields has incorrect length");
        require(validatorFields.length == 2**VALIDATOR_FIELD_TREE_HEIGHT, "BeaconChainProofs.verifySlotAndWithdrawalFields: validatorFields has incorrect length");


        require(proofs.blockHeaderRootIndex < 2**BLOCK_ROOTS_TREE_HEIGHT, "BeaconChainProofs.verifySlotAndWithdrawalFields: blockRootIndex is too large");
        require(proofs.withdrawalIndex < 2**WITHDRAWALS_TREE_HEIGHT, "BeaconChainProofs.verifySlotAndWithdrawalFields: withdrawalIndex is too large");
        require(proofs.validatorIndex < 2**VALIDATOR_TREE_HEIGHT, "BeaconChainProofs.verifySlotAndWithdrawalFields: validatorIndex is too large");

       
        // verify the block header proof length
        require(proofs.blockHeaderProof.length == 32 * (BEACON_STATE_FIELD_TREE_HEIGHT + BLOCK_ROOTS_TREE_HEIGHT), "BeaconChainProofs.verifySlotAndWithdrawalFields: blockHeaderProof has incorrect length");
        require(proofs.withdrawalProof.length == 32 * (EXECUTION_PAYLOAD_HEADER_FIELD_TREE_HEIGHT + WITHDRAWALS_TREE_HEIGHT + 1), "BeaconChainProofs.verifySlotAndWithdrawalFields: withdrawalProof has incorrect length");
        require(proofs.slotProof.length == 32 * (BEACON_BLOCK_HEADER_FIELD_TREE_HEIGHT), "BeaconChainProofs.verifySlotAndWithdrawalFields: slotProof has incorrect length");
        require(proofs.validatorProof.length == 32 * (BEACON_STATE_FIELD_TREE_HEIGHT + VALIDATOR_TREE_HEIGHT + 1), "BeaconChainProofs.verifySlotAndWithdrawalFields: validatorProof has incorrect length");
        require(proofs.executionPayloadProof.length == 32 * (BEACON_BLOCK_HEADER_FIELD_TREE_HEIGHT + BEACON_BLOCK_BODY_FIELD_TREE_HEIGHT), "BeaconChainProofs.verifySlotAndWithdrawalFields: executionPayloadProof has incorrect length");

        //First we verify the block header proof, which is common to the withdrawal proof and the slot proof

        //Compute the block_header_index relative to the beaconStateRoot.  It concatenates the indexes of all the
        // intermediate root indexes from the bottom of the sub trees (the block header container) to the top of the tree
        uint256 block_header_index = BLOCK_ROOTS_INDEX << (BLOCK_ROOTS_TREE_HEIGHT)  | uint256(proofs.blockHeaderRootIndex);
        require(Merkle.verifyInclusionSha256(proofs.blockHeaderProof, beaconStateRoot, proofs.blockHeaderRoot, block_header_index), "BeaconChainProofs.verifySlotAndWithdrawalFields: Invalid block header merkle proof");

        //Next we verify the slot against the blockHeaderRoot
        uint256 slot_index = uint256(SLOT_INDEX);
        require(Merkle.verifyInclusionSha256(proofs.slotProof, proofs.blockHeaderRoot, proofs.slotRoot, slot_index), "BeaconChainProofs.verifySlotAndWithdrawalFields: Invalid slot merkle proof");

        // //Next we verify the executionPayloadHeader against the blockHeaderRoot
        uint256 executionPayloadIndex = BODY_ROOT_INDEX << (BEACON_BLOCK_BODY_FIELD_TREE_HEIGHT)| EXECUTION_PAYLOAD_INDEX ;
        require(Merkle.verifyInclusionSha256(proofs.executionPayloadProof, proofs.blockHeaderRoot, proofs.executionPayloadRoot, executionPayloadIndex), "BeaconChainProofs.verifySlotAndWithdrawalFields: Invalid executionPayload merkle proof");

        // Next we verify the blockNumber against the executionPayload root
        uint256 blockNumberIndex = uint256(BLOCK_NUMBER_INDEX);
        require(Merkle.verifyInclusionSha256(proofs.blockNumberProof, proofs.executionPayloadRoot, proofs.blockNumberRoot, blockNumberIndex));

        //Next we verify the withdrawal fields against the blockHeaderRoot
        //This computes the withdrawal_index relative to the blockHeaderRoot.  It concatenates the indexes of all the 
        // intermediate root indexes from the bottom of the sub trees (the withdrawal container) to the top, the blockHeaderRoot
        uint256 withdrawalIndex = WITHDRAWALS_INDEX << (WITHDRAWALS_TREE_HEIGHT + 1) | uint256(proofs.withdrawalIndex);
        bytes32 withdrawalRoot = Merkle.merkleizeSha256(withdrawalFields);
        require(Merkle.verifyInclusionSha256(proofs.withdrawalProof, proofs.executionPayloadRoot, withdrawalRoot, withdrawalIndex), "BeaconChainProofs.verifySlotAndWithdrawalFields: Invalid withdrawal merkle proof");


        //Next we verify the validator fields against the beaconStateRoot (for the withdrawable epoch proof)
        verifyValidatorFields(proofs.validatorIndex, beaconStateRoot, proofs.validatorProof, validatorFields);
    }

}