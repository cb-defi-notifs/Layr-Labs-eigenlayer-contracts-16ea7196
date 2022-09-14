// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./EigenLayerParser.sol";

contract Allocate is
    Script,
    DSTest,
    EigenLayerParser
{
    using BytesLib for bytes;

    //performs basic deployment before each test
    function run() external {
        // read meta data from json
        parseEigenLayerParams();

        uint256 wethAmount = eigenTotalSupply / (numStaker + numDis + 50); // save 100 portions
        vm.startBroadcast();
        // deployer allocate weth, eigen to staker
        for (uint i = 0; i < numStaker ; ++i) {
            address stakerAddr = stdJson.readAddress(configJson, string.concat(".staker[", string.concat(vm.toString(i), "].address")));
            weth.balanceOf(address(this));
            weth.transfer(stakerAddr, wethAmount);
            eigen.transfer(stakerAddr, wethAmount);
            emit log("stakerAddr");
            emit log_address(stakerAddr);
        }
        // deployer allocate weth, eigen to disperser
        for (uint i = 0; i < numDis ; ++i) {
            address disAddr = stdJson.readAddress(configJson, string.concat(".dis[", string.concat(vm.toString(i), "].address")));    
            weth.transfer(disAddr, wethAmount);
            emit log("disAddr");
            emit log_address(disAddr);
        }

        vm.stopBroadcast();
    }
}
