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

    constructor() {
        proofConfigJson = vm.readFile("./src/test/test-data/owners.json");
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

    function getBlockHeaderProof() public returns(bytes32[] memory){
        for (uint i = 0; i < 18; i++) {
            prefix = string.concat(".BlockHeaderProof[", string.concat(vm.toString(i), "]"));
            blockHeaderProof.push(stdJson.readBytes32(proofConfigJson, prefix)); 
        }
    }

    function getSlotProof() public returns(bytes32[] memory){
        for (uint i = 0; i < 3; i++) {
            prefix = string.concat(".SlotProof[", string.concat(vm.toString(i), "]"));
            slotProof.push(stdJson.readBytes32(proofConfigJson, prefix)); 
        }
    }

    function getWithdrawalProof() public returns(bytes32[] memory){
        for (uint i = 0; i < 16; i++) {
            prefix = string.concat(".WithdrawalProof[", string.concat(vm.toString(i), "]"));
            withdrawalProof.push(stdJson.readBytes32(proofConfigJson, prefix)); 
        }
    }

    function getValidatorProof() public returns(bytes32[] memory){
        for (uint i = 0; i < 46; i++) {
            prefix = string.concat(".ValidatorProof[", string.concat(vm.toString(i), "]"));
            validatorProof.push(stdJson.readBytes32(proofConfigJson, prefix)); 
        }
    }
    
    function getWithdrawalFields() public returns(bytes32[] memory){
        for (uint i = 0; i < 4; i++) {
            prefix = string.concat(".WithdrawalFields[", string.concat(vm.toString(i), "]"));
            withdrawalFields.push(stdJson.readBytes32(proofConfigJson, prefix)); 
        }
    }

    function getValidatorFields() public returns(bytes32[] memory){
        for (uint i = 0; i < 8; i++) {
            prefix = string.concat(".ValidatorFields[", string.concat(vm.toString(i), "]"));
            validatorFields.push(stdJson.readBytes32(proofConfigJson, prefix)); 
        }
    }





}