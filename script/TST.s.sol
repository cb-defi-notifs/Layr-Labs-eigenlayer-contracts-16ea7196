// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.9;

// import "./EigenLayerParser.sol";

// contract TST is Script, DSTest, EigenLayerParser {
//     using BytesLib for bytes;

//     //performs basic deployment before each test
//     function run() external {
//         // read meta data from json
//         parseEigenLayerParams();
//         BLSRegistryWithBomb dlReg = BLSRegistryWithBomb(stdJson.readAddress(addressJson, ".dlReg"));
//         emit log_address(address(dlReg));
//         dlReg.ephemeralKeyRegistry();
//     }
// }
