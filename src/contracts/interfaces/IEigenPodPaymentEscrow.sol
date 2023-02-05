// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

interface IEigenPodPaymentEscrow {
    // struct used to pack data into a single storage slot
    struct Payment {
        uint224 amount;
        uint32 blockCreated;
    }

    // struct used to store a single users payment data
    struct UserPayments {
        uint256 paymentsCompleted;
        Payment[] payments;
    }

    /** 
     * @notice Creates an escrowed payment for `msg.value` to the `recipient`.
     * @dev Only callable by the `podOwner`'s EigenPod contract.
     */
    function createPayment(address podOwner, address recipient) external payable;

    /**
     * @notice Called in order to withdraw escrowed payments made to the `recipient` that have passed the `withdrawalDelayBlocks` period.
     * @param recipient The address to claim payments for.
     * @param maxNumberOfPaymentsToClaim Used to limit the maximum number of payments to loop through claiming.
     */
    function claimPayments(address recipient, uint256 maxNumberOfPaymentsToClaim) external;

    /**
     * @notice Called in order to withdraw escrowed payments made to the caller that have passed the `withdrawalDelayBlocks` period.
     * @param maxNumberOfPaymentsToClaim Used to limit the maximum number of payments to loop through claiming.
     */
    function claimPayments(uint256 maxNumberOfPaymentsToClaim) external;

    /// @notice Owner-only function for modifying the value of the `withdrawalDelayBlocks` variable.
    function setWithdrawalDelayBlocks(uint256 newValue) external;

    /// @notice Getter function for the mapping `_userPayments`
    function userPayments(address user) external view returns (UserPayments memory);

    /// @notice Getter function for fetching the payment at the `index`th entry from the `_userPayments[user].payments` array
    function userPaymentByIndex(address user, uint256 index) external view returns (Payment memory);

    /// @notice Convenience function for checking whethere or not the payment at the `index`th entry from the `_userPayments[user].payments` array is currently claimable
    function canClaimPayment(address user, uint256 index) external view returns (bool);

    /**
     * @notice Delay enforced by this contract for completing any payment. Measured in blocks, and adjustable by this contract's owner,
     * up to a maximum of `MAX_WITHDRAWAL_DELAY_BLOCKS`. Minimum value is 0 (i.e. no delay enforced).
     */
    function withdrawalDelayBlocks() external view returns (uint256);
}