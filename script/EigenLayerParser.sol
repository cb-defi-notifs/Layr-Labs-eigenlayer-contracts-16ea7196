// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.9;

// import "../src/contracts/interfaces/IEigenLayrDelegation.sol";
// import "../src/contracts/core/EigenLayrDelegation.sol";

// import "../src/contracts/core/InvestmentManager.sol";
// import "../src/contracts/strategies/InvestmentStrategyBase.sol";
// import "../src/contracts/core/Slasher.sol";

// import "../src/contracts/DataLayr/DataLayrServiceManager.sol";
// import "../src/contracts/DataLayr/BLSRegistryWithBomb.sol";
// import "../src/contracts/DataLayr/DataLayrPaymentManager.sol";
// import "../src/contracts/DataLayr/EphemeralKeyRegistry.sol";
// import "../src/contracts/DataLayr/DataLayrChallengeUtils.sol";
// import "../src/contracts/DataLayr/DataLayrLowDegreeChallenge.sol";

// import "forge-std/Script.sol";
// import "forge-std/StdJson.sol";

// contract EigenLayerParser is Script, DSTest {
//     using BytesLib for bytes;

//     Vm cheats = Vm(HEVM_ADDRESS);

//     uint256 numDis;
//     uint256 numDln;
//     uint256 numStaker;
//     uint256 numCha;

//     uint256 public constant eigenTotalSupply = 1000e18;
//     EigenLayrDelegation public delegation;
//     InvestmentManager public investmentManager;
//     IERC20 public weth;
//     InvestmentStrategyBase public wethStrat;
//     IERC20 public eigen;
//     InvestmentStrategyBase public eigenStrat;

//     string internal configJson;
//     string internal addressJson;

//     function parseEigenLayerParams() internal {
//         configJson = vm.readFile("data/participants.json");
//         numDis = stdJson.readUint(configJson, ".numDis");
//         numDln = stdJson.readUint(configJson, ".numDln");
//         numStaker = stdJson.readUint(configJson, ".numStaker");

//         addressJson = vm.readFile("data/addresses.json");
//         delegation = EigenLayrDelegation(stdJson.readAddress(addressJson, ".delegation"));
//         investmentManager = InvestmentManager(stdJson.readAddress(addressJson, ".investmentManager"));
//         weth = IERC20(stdJson.readAddress(addressJson, ".weth"));
//         wethStrat = InvestmentStrategyBase(stdJson.readAddress(addressJson, ".wethStrat"));
//         eigen = IERC20(stdJson.readAddress(addressJson, ".eigen"));
//         eigenStrat = InvestmentStrategyBase(stdJson.readAddress(addressJson, ".eigenStrat"));
//     }
// }
