// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


import "../src/contracts/core/Eigen.sol";

import "../src/contracts/interfaces/IEigenLayrDelegation.sol";
import "../src/contracts/core/EigenLayrDelegation.sol";

import "../src/contracts/investment/InvestmentManager.sol";
import "../src/contracts/investment/InvestmentStrategyBase.sol";
import "../src/contracts/investment/HollowInvestmentStrategy.sol";
import "../src/contracts/investment/Slasher.sol";

import "../src/contracts/middleware/ServiceFactory.sol";
import "../src/contracts/middleware/Repository.sol";
import "../src/contracts/middleware/DataLayr/DataLayrServiceManager.sol";
import "../src/contracts/middleware/BLSRegistryWithBomb.sol";
import "../src/contracts/middleware/DataLayr/DataLayrPaymentManager.sol";
import "../src/contracts/middleware/EphemeralKeyRegistry.sol";
import "../src/contracts/middleware/DataLayr/DataLayrChallengeUtils.sol";
import "../src/contracts/middleware/DataLayr/DataLayrLowDegreeChallenge.sol";

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

contract EigenLayerParser is Script, DSTest
{
    using BytesLib for bytes;

    Vm cheats = Vm(HEVM_ADDRESS);

    uint numDis;
    uint numDln;
    uint numStaker;
    uint numCha;

    uint256 public constant eigenTotalSupply = 1000e18;
    EigenLayrDelegation public delegation;
    InvestmentManager public investmentManager;
    IERC20 public weth;
    InvestmentStrategyBase public wethStrat;
    IERC20 public eigen;
    InvestmentStrategyBase public eigenStrat;

    string internal configJson;
    string internal addressJson;

    function parseEigenLayerParams() internal {
        configJson = vm.readFile("data/participants.json");
        numDis = stdJson.readUint(configJson, ".numDis");
        numDln = stdJson.readUint(configJson, ".numDln");
        numStaker = stdJson.readUint(configJson, ".numStaker");

        addressJson = vm.readFile("data/addresses.json");
        delegation = EigenLayrDelegation(stdJson.readAddress(addressJson, ".delegation"));
        investmentManager = InvestmentManager(stdJson.readAddress(addressJson, ".investmentManager"));
        weth = IERC20(stdJson.readAddress(addressJson, ".weth"));
        wethStrat = InvestmentStrategyBase(stdJson.readAddress(addressJson, ".wethStrat"));
        eigen = IERC20(stdJson.readAddress(addressJson, ".eigen"));
        eigenStrat = InvestmentStrategyBase(stdJson.readAddress(addressJson, ".eigenStrat"));
    }
}