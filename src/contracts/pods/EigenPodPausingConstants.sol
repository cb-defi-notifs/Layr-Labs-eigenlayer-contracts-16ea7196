// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

/**
 * @title Constants shared between 'EigenPod' and 'EigenPodManager' contracts.
 * @author Layr Labs, Inc.
 */
abstract contract EigenPodPausingConstants {
    /// @notice Index for flag that pauses the `verifyCorrectWithdrawalCredentials` function *of the EigenPods* when set. see EigenPod code for details.
    uint8 internal constant PAUSED_EIGENPODS_VERIFY_CREDENTIALS = 2;
    /// @notice Index for flag that pauses the `verifyOvercommittedStake` function *of the EigenPods* when set. see EigenPod code for details.
    uint8 internal constant PAUSED_EIGENPODS_VERIFY_OVERCOMMITTED = 3;
    /// @notice Index for flag that pauses the `verifyBeaconChainFullWithdrawal` function *of the EigenPods* when set. see EigenPod code for details.
    uint8 internal constant PAUSED_EIGENPODS_VERIFY_WITHDRAWAL = 4;
}