// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IInvestmentManager.sol";
import "./IEigenPod.sol";

/**
 * @title Interface for factory that creates and manages solo staking pods that have their withdrawal credentials pointed to EigenLayer.
 * @author Layr Labs, Inc.
 */

interface IEigenPodManager {
    //This struct helps manage the info about a certain pod owner's pod
    struct EigenPodInfo {
        uint128 balance; //total balance of all validators in the pod
        uint128 stakedBalance; //amount of balance deposited into EigenLayer
        IEigenPod pod; //the address of the pow owner's pod
    }

    function investmentManager() external returns(IInvestmentManager);
    function createPod() external;
    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable;
    function updateBeaconChainBalance(address podOwner, uint64 balanceToRemove, uint64 balanceToAdd) external;
    function restakeBeaconChainETH(address podOwner, uint128 amount) external;
    function withdrawRestakedBeaconChainETH(address podOwner, address recipient, uint256 amount) external;
    function getPod(address podOwner) external view returns(IEigenPod);
    function getPodInfo(address podOwner) external view returns(EigenPodInfo memory);
    function getBeaconChainStateRoot() external view returns(bytes32);
}
