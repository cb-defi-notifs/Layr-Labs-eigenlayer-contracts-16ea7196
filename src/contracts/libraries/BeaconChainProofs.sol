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
     * @param validatorIndex the index of the proven validator
     * @param beaconStateRoot is the beacon chain state root.
     * @param proof is the data used in proving the validator's fields
     * Proof Format:
     * < 
     * bytes32[] validatorMerkleProof, the inclusion proof for the individual validator container root in the validator registry tree
     * bytes32[] beaconStateMerkleProofForValidatorTreeRoot, the inclusion proof for the validator registry root in the beacon state
     * bytes32 validatorContainerRoot, the ndividual validator container root being proven 
     * >
     * @param validatorFields the claimed fields of the validator
     */
    function verifyValidatorFields(
        uint40 validatorIndex,
        bytes32 beaconStateRoot,
        bytes calldata proof, 
        bytes32[] calldata validatorFields
    ) internal view {
        require(validatorFields.length == 2**VALIDATOR_FIELD_TREE_HEIGHT, "BeaconChainProofs.verifyValidatorFieldsOneShot: Validator fields has incorrect length");

        // Note: the length of the validator merkle proof is BeaconChainProofs.VALIDATOR_TREE_HEIGHT + 1 - there is an additional layer added by hashing the root with the length of the validator list
        require(proof.length == 32 * ((VALIDATOR_TREE_HEIGHT + 1) + BEACON_STATE_FIELD_TREE_HEIGHT), "BeaconChainProofs.verifyValidatorFieldsOneShot: Proof has incorrect length");
        uint256 index = (VALIDATOR_TREE_ROOT_INDEX << (VALIDATOR_TREE_HEIGHT + 1)) | uint256(validatorIndex);
        // merkleize the validatorFields to get the leaf to prove
        bytes32 validatorRoot = Merkle.merkleizeSha256(validatorFields);

        // verify the proof
        require(Merkle.verifyInclusionSha256(proof, beaconStateRoot, validatorRoot, index), "BeaconChainProofs.verifyValidatorFieldsOneShot: Invalid merkle proof");
    }

    /// @param beaconStateRoot is the latest beaconStateRoot posted by the oracle
    function verifyWithdrawalProofs(
        bytes32 beaconStateRoot, 
        bytes calldata historicalStateProof,
        bytes calldata withdrawalProof, 
        bytes32[] calldata withdrawalContainerFields
    ) internal view {
        require(withdrawalContainerFields.length == 2**WITHDRAWAL_FIELD_TREE_HEIGHT, "withdrawalContainerFields has incorrect length");
        // Note: WITHDRAWALS_TREE_HEIGHT + 1 accounts for the hashing of the withdrawal list root with the number of withdrawals in the withdrawal list
        require(withdrawalProof.length == 32 * (BEACON_STATE_FIELD_TREE_HEIGHT + EXECUTION_PAYLOAD_HEADER_FIELD_TREE_HEIGHT + WITHDRAWALS_TREE_HEIGHT + 1), "withdrawalProof length is incorrect");

        // check that beacon state root from oracle is present in historical roots
        // TODO: uncomment
        // verifyBeaconChainRootProof(beaconStateRoot, historicalStateProof);


        bytes32 withdrawalContainerRoot = Merkle.merkleizeSha256(withdrawalContainerFields);
        uint256 withdrawalIndex = Endian.fromLittleEndianUint64(withdrawalContainerFields[0]);
        uint256 withdrawalConatinerIndex = (WITHDRAWALS_ROOT_INDEX << (WITHDRAWALS_TREE_HEIGHT + 1)) | withdrawalIndex;
        withdrawalConatinerIndex = 
                        ((EXECUTION_PAYLOAD_HEADER_INDEX << (EXECUTION_PAYLOAD_HEADER_FIELD_TREE_HEIGHT + WITHDRAWALS_TREE_HEIGHT + 1)) | withdrawalConatinerIndex);


        bool valid = Merkle.verifyInclusionSha256(withdrawalProof, beaconStateRoot, withdrawalContainerRoot, withdrawalConatinerIndex);

        require(valid, "Withdrawal merkle inclusion proof failed");
    }

    function verifyBeaconChainRootProof(
        bytes32 beaconStateRoot, 
        bytes calldata proofs,
        uint256 pointer
    )internal view returns(uint256){

        bytes32 historicalRootsRoot = proofs.toBytes32(pointer);
        pointer += 32;
        //check if the historical_roots array's root is in the beacon state
        require(Merkle.verifyInclusionSha256(
            proofs.slice(pointer, 32 * BeaconChainProofs.BEACON_STATE_FIELD_TREE_HEIGHT), 
            beaconStateRoot, 
            historicalRootsRoot, 
            BeaconChainProofs.HISTORICAL_ROOTS_INDEX),
            "BeaconChainProofs.verifyBeaconChainRootProof: stateroots Root proof invalid"
        );
        pointer += 32 * BeaconChainProofs.BEACON_STATE_FIELD_TREE_HEIGHT;



        bytes32 historicalBatchRoot = proofs.toBytes32(pointer);
        pointer += 32;
        // check if the historicalBatch's root is in the historical_roots array
        require(Merkle.verifyInclusionSha256(
            proofs.slice(pointer + 32, 32 * BeaconChainProofs.HISTORICAL_ROOTS_TREE_HEIGHT), 
            historicalRootsRoot, 
            historicalBatchRoot, 
            proofs.toUint256(pointer)),
            "BeaconChainProofs.verifyBeaconChainRootProof: historicalBatchRoot proof invalid"
        );
        pointer += 32 + 32 * BeaconChainProofs.HISTORICAL_ROOTS_TREE_HEIGHT;



        bytes32 stateRootsRoot = proofs.toBytes32(pointer);
        pointer += 32;
        //now we check that the stateRoots array's root is included in the HistoricalBatch
        require(Merkle.verifyInclusionSha256(
            proofs.slice(pointer, 32), //the proof is only checking that hash(blockRootsRoot, stateRootsRoot) = historicalBatchRoot
            historicalBatchRoot, 
            stateRootsRoot, 
            BeaconChainProofs.HISTORICALBATCH_STATEROOTS_INDEX),
            "BeaconChainProofs.verifyBeaconChainRootProof: staterootsRoot proof is invalid"
        );
        pointer += 32 * BeaconChainProofs.HISTORICAL_ROOTS_TREE_HEIGHT;

    

        bytes32 beaconStateRootToVerify = proofs.toBytes32(pointer);
        pointer += 32;
        require(Merkle.verifyInclusionSha256(
            proofs.slice(pointer + 32, 32 * BeaconChainProofs.STATE_ROOTS_TREE_HEIGHT), 
            stateRootsRoot, 
            beaconStateRootToVerify, 
            proofs.toUint256(pointer)),
            "BeaconChainProofs.verifyBeaconChainRootProof: beaconstateRoot to verify proof is invalid"
        );
        pointer += 32 + 32 * BeaconChainProofs.STATE_ROOTS_TREE_HEIGHT;

        return pointer;
    }
}