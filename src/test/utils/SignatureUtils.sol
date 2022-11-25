// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract SignatureUtils is Test {
    //numSigners => array of signatures for 5 datastores
    mapping(uint256 => uint256[]) signatures;
    

    string internal signatureJson;

    constructor() {
        signatureJson = vm.readFile("./src/test/data/signatures.json");
    }

    function signaturePrefix(uint256 numSigners) public returns(string memory) {
        return string.concat(".signatures[", string.concat(vm.toString(numSigners), "]."));
    }

    //returns aggPK.X0, aggPK.X1, aggPK.Y0, aggPK.Y1
    function getAggregatePublicKeyG2()
        internal
        returns (uint256 aggPKX0, uint256 aggPKX1, uint256 aggPKY0, uint256 aggPKY1)
    {
        aggPKX0 = getUintFromJson(signatureJson, "aggregateSignature.AggPubkeyG2.X.A0");
        aggPKX1 = getUintFromJson(signatureJson, "aggregateSignature.AggPubkeyG2.X.A1");
        aggPKY0 = getUintFromJson(signatureJson, "aggregateSignature.AggPubkeyG2.Y.A0");
        aggPKY1 = getUintFromJson(signatureJson, "aggregateSignature.AggPubkeyG2.Y.A1");

        return (aggPKX0, aggPKX1, aggPKY0, aggPKY1);
    }

    function getAggPubKeyG2WithoutNonSigners(uint32 nonSignerDataIndex)
        internal
        returns (uint256 aggPKX0, uint256 aggPKX1, uint256 aggPKY0, uint256 aggPKY1)
    {
        aggPKX0 = getAggPubKeyG2WithoutNonSignersFromJson(signatureJson, nonSignerDataIndex, "AggPubkeyG2WithoutNonSigners.X.A0");
        aggPKX1 = getAggPubKeyG2WithoutNonSignersFromJson(signatureJson, nonSignerDataIndex, "AggPubkeyG2WithoutNonSigners.X.A1");
        aggPKY0 = getAggPubKeyG2WithoutNonSignersFromJson(signatureJson, nonSignerDataIndex, "AggPubkeyG2WithoutNonSigners.Y.A0");
        aggPKY1 = getAggPubKeyG2WithoutNonSignersFromJson(signatureJson, nonSignerDataIndex, "AggPubkeyG2WithoutNonSigners.Y.A1");

        return (aggPKX0, aggPKX1, aggPKY0, aggPKY1);
    }

    //returns aggPK.X, aggPK.Y
    function getAggregatePublicKeyG1()
        internal 
        returns (uint256 aggPKX, uint256 aggPKY)
    {
        aggPKX = getUintFromJson(signatureJson, "aggregateSignature.AggPubkeyG1.X");
        aggPKY = getUintFromJson(signatureJson, "aggregateSignature.AggPubkeyG1.Y");

        return (aggPKX, aggPKY);
    }

    //get the aggregate signature of all 15 signers
    function getAggSignature() internal returns (uint256 sigX, uint256 sigY) {

        sigX = getUintFromJson(signatureJson, "aggregateSignature.Signature.X");
        sigY = getUintFromJson(signatureJson, "aggregateSignature.Signature.Y");

        return (sigX, sigY);
    }

    function getNonSignerPK(uint32 pkIndex, uint32 nonSignerDataIndex) internal returns (uint256 PKX, uint256 PKY) {
        PKX = getNonSignerPKFromJson(signatureJson, pkIndex, nonSignerDataIndex, "PubkeyG1.X");
        PKY = getNonSignerPKFromJson(signatureJson, pkIndex, nonSignerDataIndex, "PubkeyG1.Y");
        return(PKX, PKY);
    }

    function getNonSignerAggSig(uint32 nonSignerDataIndex) internal returns (uint256 sigmaX, uint256 sigmaY) {
        sigmaX = getNonSignerAggSigFromJson(signatureJson, nonSignerDataIndex, "AggSignature.X");
        sigmaY = getNonSignerAggSigFromJson(signatureJson, nonSignerDataIndex, "AggSignature.Y");

        return(sigmaX, sigmaY);
    }

    function setSignatures() internal {
        //X-coordinate for signature
        signatures[15].push(uint256(8948534429609633165965303176051337508823928923777758842886744023440854204267));
        //Y-coordinate for signature
        signatures[15].push(uint256(4622408548686949531175238473896974870555776834372530175532799335740509601351));


        /// @dev these next 4 aggregate signatures are specifically for testConfirmDataStoreLoop, where 
        ///      globalDataStoreID and index are incremented, which changes the msgHash, requiring new agg signatures.

        // //X-coordinate for signature
        // signatures[15].push(uint256(3768102256762337404052867633199540834071715013336059969755534978335414815915));
        // //Y-coordinate for signature
        // signatures[15].push(uint256(1347732725763368146376839019105722102118183430445244463171147039833656430554));
        
        // //X-coordinate for signature
        // signatures[15].push(uint256(17726052552451194045498831446622391523712052718156013644001539561406531574296));
        // //Y-coordinate for signature
        // signatures[15].push(uint256(21548143511877874702515855361829893658157938210262199838254421299589869143948));

        // //X-coordinate for signature
        // signatures[15].push(uint256(18456695013140797630139570327999178712970087934218862167996303262756077265885));
        // //Y-coordinate for signature
        // signatures[15].push(uint256(6692040044674932411543245093209937967397201373852910194529170609645372186580));

        // //X-coordinate for signature
        // signatures[15].push(uint256(16936593860632559597797231574125317688131352946934229986716277496846837045926));
        // //Y-coordinate for signature
        // signatures[15].push(uint256(8419080474874111328448521941401302337127845046207972316360714449012068914811));

        // //X-coordinate for signature
        // signatures[12].push(uint256(18984184697644363675345717428833426720816735538703890129083867845101356547512));
        // //Y-coordinate for signature
        // signatures[12].push(uint256(13901218866265249360377869173958633007705926687970641308083042116030556327083));

        // //X-coordinate for signature
        // signatures[2].push(uint256(15462773903105570423983200028906973961348449005977379407744153690820070538946));
        // //Y-coordinate for signature
        // signatures[2].push(uint256(1958496896045946333699360997077644865789632650763255938686790892516574013948));
        
    }

    function getUintFromJson(string memory json, string memory key) internal returns(uint256){
        string memory word =  stdJson.readString(json, key);
        return convertStringToUint(word);
    }

    function getNonSignerPKFromJson(string memory json, uint256 pubkeyIndex, uint256 nonSignersDataIndex, string memory key) internal returns(uint256){
        
        string memory temp1 = string.concat(vm.toString(nonSignersDataIndex), "].");
        string memory temp2 = string.concat("nonSignersData[", temp1);
        string memory temp3 = string.concat(temp2, "NonSigners[");
        string memory temp4 = string.concat(vm.toString(pubkeyIndex), "].");
        string memory pubKeyEntry = string.concat(temp3, temp4);
        string memory word =  stdJson.readString(json, string.concat(pubKeyEntry, key));


        return convertStringToUint(word);
    }

    function getNonSignerAggSigFromJson(string memory json, uint256 nonSignersDataIndex, string memory key) internal returns(uint256){
        
        string memory temp1 = string.concat(vm.toString(nonSignersDataIndex), "].");
        string memory pubKeyEntry = string.concat("nonSignersData[", temp1);
        string memory word =  stdJson.readString(json, string.concat(pubKeyEntry, key));
        return convertStringToUint(word);
    }

    function getAggPubKeyG2WithoutNonSignersFromJson(string memory json, uint256 nonSignersDataIndex, string memory key) internal returns(uint256){
        
        string memory temp1 = string.concat(vm.toString(nonSignersDataIndex), "].");
        string memory pubKeyEntry = string.concat("nonSignersData[", temp1);
        string memory word =  stdJson.readString(json, string.concat(pubKeyEntry, key));
        return convertStringToUint(word);
    }

    function convertStringToUint(string memory s) public pure returns (uint) {
        bytes memory b = bytes(s);
        uint result = 0;
        for (uint i = 0; i < b.length; i++) {
            if (uint256(uint8(b[i])) >= 48 && uint256(uint8(b[i])) <= 57) {
                result = result * 10 + (uint256(uint8(b[i])) - 48); 
            }
        }
        return result;
    }
}
