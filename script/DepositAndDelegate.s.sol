// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./EigenLayerParser.sol";

contract DepositAndDelegate is
    Script,
    DSTest,
    EigenLayerParser
{
    using BytesLib for bytes;

    //performs basic deployment before each test
    function run() external {
        parseEigenLayerParams();

        uint256 wethAmount = eigenTotalSupply / (numStaker + numDis + 50); // save 100 portions

        address dlnAddr;

        //get the corresponding dln
        //is there an easier way to do this?
        for (uint i = 0; i < numStaker; i++) {
            address stakerAddr = stdJson.readAddress(configJson, string.concat(".staker[", string.concat(vm.toString(i), "].address")));
            if(stakerAddr == msg.sender) {
                dlnAddr = stdJson.readAddress(configJson, string.concat(".dln[", string.concat(vm.toString(i), "].address")));
            } 
        }

        vm.startBroadcast(msg.sender);
        eigen.approve(address(investmentManager), wethAmount);
        investmentManager.depositIntoStrategy(msg.sender, eigenStrat, eigen, wethAmount);
        weth.approve(address(investmentManager), wethAmount);
        investmentManager.depositIntoStrategy(msg.sender, wethStrat, weth, wethAmount);
        investmentManager.investorStratShares(msg.sender, wethStrat);
        delegation.delegateTo(dlnAddr);
        vm.stopBroadcast();
    }
}