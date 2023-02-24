// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "../../contracts/libraries/BN254.sol";
import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";


contract ProofParsing is Test{
    string internal proofConfigJson;
    string prefix;

    bytes32[] blockHeaderProof;
    bytes32[] slotProof;
    bytes32[] withdrawalProof;
    bytes32[] validatorProof;

    bytes32[] withdrawalFields;
    bytes32[] validatorFields;

    bytes32[] executionPayloadProof;
    bytes32[] blockNumberProofs;
    bytes32[] withdrawalCredentialProof;


    bytes32 slotRoot;
    bytes32 executionPayloadRoot;
    bytes32 blockNumberRoots;

    constructor() {
        proofConfigJson = vm.readFile("./src/test/test-data/proofs.json");
    }

    function getSlot() public returns(uint256) {
        return stdJson.readUint(proofConfigJson, ".slot");
    }

    function getValidatorIndex() public returns(uint256){
        return stdJson.readUint(proofConfigJson, ".validatorIndex");
    }

    function getWithdrawalIndex() public returns(uint256){
        return stdJson.readUint(proofConfigJson, ".withdrawalIndex");
    }

    function getBlockHeaderRootIndex() public returns(uint256){
        return stdJson.readUint(proofConfigJson, ".blockHeaderRootIndex");
    }

    function getBeaconStateRoot() public returns(bytes32){
        return stdJson.readBytes32(proofConfigJson, ".beaconStateRoot");
    }

    function getBlockHeaderRoot() public returns(bytes32){
        return stdJson.readBytes32(proofConfigJson, ".blockHeaderRoot");
    }

    function getBlockBodyRoot() public returns(bytes32){
        return stdJson.readBytes32(proofConfigJson, ".blockBodyRoot");
    }

    function getSlotRoot() public returns(bytes32){
        return stdJson.readBytes32(proofConfigJson, ".slotRoot");
    }

    function getBlockNumberRoot() public returns(bytes32){
        return stdJson.readBytes32(proofConfigJson, ".blockNumberRoot");
    }

    function getExecutionPayloadRoot() public returns(bytes32){
        return stdJson.readBytes32(proofConfigJson, ".executionPayloadRoot");
    }
    function getExecutionPayloadProof () public returns(bytes32[] memory){
        for (uint i = 0; i < 7; i++) {
            prefix = string.concat(".ExecutionPayloadProof[", string.concat(vm.toString(i), "]"));
            executionPayloadProof.push(stdJson.readBytes32(proofConfigJson, prefix)); 
        }
        return executionPayloadProof;
    }

    function getBlockNumberProof () public returns(bytes32[] memory){
        for (uint i = 0; i < 4; i++) {
            prefix = string.concat(".BlockNumberProof[", string.concat(vm.toString(i), "]"));
            blockNumberProofs.push(stdJson.readBytes32(proofConfigJson, prefix)); 
        }
        return blockNumberProofs;
    }

    function getBlockHeaderProof() public returns(bytes32[] memory){
        for (uint i = 0; i < 18; i++) {
            prefix = string.concat(".BlockHeaderProof[", string.concat(vm.toString(i), "]"));
            blockHeaderProof.push(stdJson.readBytes32(proofConfigJson, prefix)); 
        }
        return blockHeaderProof;
    }

    function getSlotProof() public returns(bytes32[] memory){
        for (uint i = 0; i < 3; i++) {
            prefix = string.concat(".SlotProof[", string.concat(vm.toString(i), "]"));
            slotProof.push(stdJson.readBytes32(proofConfigJson, prefix)); 
        }
        return slotProof;
    }

    function getWithdrawalProof() public returns(bytes32[] memory){
        for (uint i = 0; i < 9; i++) {
            prefix = string.concat(".WithdrawalProof[", string.concat(vm.toString(i), "]"));
            withdrawalProof.push(stdJson.readBytes32(proofConfigJson, prefix)); 
        }
        return withdrawalProof;
    }

    function getValidatorProof() public returns(bytes32[] memory){
        for (uint i = 0; i < 46; i++) {
            prefix = string.concat(".ValidatorProof[", string.concat(vm.toString(i), "]"));
            validatorProof.push(stdJson.readBytes32(proofConfigJson, prefix)); 
        }
        return validatorProof;
    }
    
    function getWithdrawalFields() public returns(bytes32[] memory){
        for (uint i = 0; i < 4; i++) {
            prefix = string.concat(".WithdrawalFields[", string.concat(vm.toString(i), "]"));
            emit log_named_bytes32("prefix", stdJson.readBytes32(proofConfigJson, prefix));
            withdrawalFields.push(stdJson.readBytes32(proofConfigJson, prefix)); 
        }
         emit log_named_uint("length withdrawal firle", withdrawalFields.length);
         return withdrawalFields;

    }

    function getValidatorFields() public returns(bytes32[] memory){
        for (uint i = 0; i < 8; i++) {
            prefix = string.concat(".ValidatorFields[", string.concat(vm.toString(i), "]"));
            validatorFields.push(stdJson.readBytes32(proofConfigJson, prefix)); 
        }
        return validatorFields;
    }
}