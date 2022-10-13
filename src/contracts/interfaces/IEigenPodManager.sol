// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IInvestmentManager.sol";
import "./IEigenPod.sol";

/**
 * @title Interface for factory that creates and manages solo staking pods that have their withdrawal credentials pointed to EigenLayer.
 * @author Layr Labs, Inc.
 */

interface IEigenPodManager {
    struct EigenPodInfo {
        uint128 balance; //total balance of all validators in the pod
        uint128 stakedBalance; //amount of balance deposited into EigenLayer
        IEigenPod pod;
    }

    function investmentManager() external returns(IInvestmentManager);
    function stake(bytes32 salt, bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable;
    function updateBeaconChainBalance(address podOwner, uint64 balanceToRemove, uint64 balanceToAdd) external;
    function depositBalanceIntoEigenLayer(address podOwner, uint128 amount) external;
    function withdraw(address podOwner, address receipient, uint256 amount) external;

    function getPod(address podOwner) external view returns(EigenPodInfo memory);
}
