// //SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../../contracts/interfaces/IEigenPodManager.sol";


contract EigenPodManagerMock is IEigenPodManager, Test {
    function slasher() external view returns(ISlasher) {}

    function createPod() external pure {}

    function stake(bytes calldata /*pubkey*/, bytes calldata /*signature*/, bytes32 /*depositDataRoot*/) external payable {}

    function restakeBeaconChainETH(address /*podOwner*/, uint256 /*amount*/) external pure {}

    function recordOvercommittedBeaconChainETH(address /*podOwner*/, uint256 /*beaconChainETHStrategyIndex*/, uint256 /*amount*/) external pure {}
    
    function withdrawRestakedBeaconChainETH(address /*podOwner*/, address /*recipient*/, uint256 /*amount*/) external pure {}

    function updateBeaconChainOracle(IBeaconChainOracle /*newBeaconChainOracle*/) external pure {}

    function getPod(address /*podOwner*/) external pure returns(IEigenPod) {
        return IEigenPod(address(0));
    }

    function beaconChainOracle() external pure returns(IBeaconChainOracle) {
        return IBeaconChainOracle(address(0));
    }   

    function getBeaconChainStateRoot() external pure returns(bytes32) {
        return bytes32(0);
    }

    function investmentManager() external pure returns(IInvestmentManager) {
        return IInvestmentManager(address(0));
    }

    function hasPod(address /*podOwner*/) external pure returns (bool) {
        return false;
    }

}