// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "./IEigenPodManagerD1.sol";

/**
 * @title The implementation contract used for restaking beacon chain ETH on EigenLayer 
 * @author Layr Labs, Inc.
 * @notice The main functionalities are:
 * - creating new ETH validators with their withdrawal credentials pointed to this contract
 * - withdrawing eth when withdrawals are initiated
 */
interface IEigenPodD1 {
    /// @notice Used to initialize the pointers to contracts crucial to the pod's functionality, in beacon proxy construction from EigenPodManager
    function initialize(IEigenPodManagerD1 _eigenPodManager, address owner) external;

    /// @notice Called by EigenPodManager when the owner wants to create another ETH validator.
    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable;

    /// @notice Called by the pod owner to withdraw the balance of the pod
    function withdraw() external;

    /// @notice The single EigenPodManager for EigenLayer
    function eigenPodManager() external view returns (IEigenPodManagerD1);

    /// @notice The owner of this EigenPod
    function podOwner() external view returns (address);
}

