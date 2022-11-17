// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../contracts/libraries/BN254.sol";
import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

contract Operators is Test {
    Vm cheats = Vm(HEVM_ADDRESS);

    string internal operatorConfigJson;

    constructor() {
        operatorConfigJson = vm.readFile("./src/test/data/operators.json");
    }

    function operatorPrefix(uint256 index) public returns(string memory) {
        return string.concat(".operators[", string.concat(vm.toString(index), "]."));
    }

    function getOperatorAddress(uint256 index) public returns(address) {
        return stdJson.readAddress(operatorConfigJson, string.concat(operatorPrefix(index), "Address"));
    }

    function getOperatorSchnorrSignature(uint256 index) public returns(uint256, BN254.G1Point memory) {
        uint256 s = stdJson.readUint(operatorConfigJson, string.concat(operatorPrefix(index), "SField"));
        BN254.G1Point memory pubkey = BN254.G1Point({
            X: stdJson.readUint(operatorConfigJson, string.concat(operatorPrefix(index), "RPoint.X")),
            Y: stdJson.readUint(operatorConfigJson, string.concat(operatorPrefix(index), "RPoint.Y"))
        });
        return (s, pubkey);
    }

    function getOperatorSecretKey(uint256 index) public returns(address) {
        return stdJson.readAddress(operatorConfigJson, string.concat(operatorPrefix(index), "SecretKey"));
    }

    function getOperatorPubkeyG1(uint256 index) public returns(BN254.G1Point memory) {
        BN254.G1Point memory pubkey = BN254.G1Point({
            X: stdJson.readUint(operatorConfigJson, string.concat(operatorPrefix(index), "PubkeyG1.X")),
            Y: stdJson.readUint(operatorConfigJson, string.concat(operatorPrefix(index), "PubkeyG1.Y"))
        });
        return pubkey;
    }

    function getOperatorPubkeyG2(uint256 index) public returns(BN254.G2Point memory) {
        BN254.G2Point memory pubkey = BN254.G2Point({
            X: [
                stdJson.readUint(operatorConfigJson, string.concat(operatorPrefix(index), "PubkeyG2.X1")),
                stdJson.readUint(operatorConfigJson, string.concat(operatorPrefix(index), "PubkeyG2.X0"))
            ],   
            Y: [
                stdJson.readUint(operatorConfigJson, string.concat(operatorPrefix(index), "PubkeyG2.Y1")),
                stdJson.readUint(operatorConfigJson, string.concat(operatorPrefix(index), "PubkeyG2.Y0"))
            ]
        }); 
        return pubkey;
    }

}
