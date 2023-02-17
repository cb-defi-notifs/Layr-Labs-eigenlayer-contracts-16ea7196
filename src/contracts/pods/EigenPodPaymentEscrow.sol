// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";
import "../interfaces/IEigenPodManager.sol";
import "../interfaces/IEigenPodPaymentEscrow.sol";
import "../permissions/Pausable.sol";

contract EigenPodPaymentEscrow is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, Pausable, IEigenPodPaymentEscrow {
    /// @notice Emitted when the `withdrawalDelayBlocks` variable is modified from `previousValue` to `newValue`.
    event WithdrawalDelayBlocksSet(uint256 previousValue, uint256 newValue);

    // index for flag that pauses withdrawals (i.e. 'payment claims') when set
    uint8 internal constant PAUSED_PAYMENT_CLAIMS = 0;

    /**
     * @notice Delay enforced by this contract for completing any payment. Measured in blocks, and adjustable by this contract's owner,
     * up to a maximum of `MAX_WITHDRAWAL_DELAY_BLOCKS`. Minimum value is 0 (i.e. no delay enforced).
     */
    uint256 public withdrawalDelayBlocks;
    // the number of 12-second blocks in one week (60 * 60 * 24 * 7 / 12 = 50,400)
    uint256 public constant MAX_WITHDRAWAL_DELAY_BLOCKS = 50400;

    /// @notice The EigenPodManager contract of EigenLayer.
    IEigenPodManager public immutable eigenPodManager;

    /// @notice Mapping: user => struct storing all payment info. Marked as internal with an external getter function named `userPayments`
    mapping(address => UserPayments) internal _userPayments;

    /// @notice event for payment creation
    event PaymentCreated(address podOwner, address recipient, uint256 amount);

    /// @notice Modifier used to permission a function to only be called by the EigenPod of the specified `podOwner`
    modifier onlyEigenPod(address podOwner) {
        require(address(eigenPodManager.getPod(podOwner)) == msg.sender, "EigenPodPaymentEscrow.onlyEigenPod: not podOwner's EigenPod");
        _;
    }

    constructor(IEigenPodManager _eigenPodManager) {
        require(address(_eigenPodManager) != address(0), "EigenPodPaymentEscrow.constructor: _eigenPodManager cannot be zero address");
        eigenPodManager = _eigenPodManager;
    }

    function initialize(address initOwner, IPauserRegistry _pauserRegistry, uint256 initPausedStatus, uint256 _withdrawalDelayBlocks) external initializer {
        _transferOwnership(initOwner);
        _initializePauser(_pauserRegistry, initPausedStatus);
        _setWithdrawalDelayBlocks(_withdrawalDelayBlocks);
    }

    /** 
     * @notice Creates an escrowed payment for `msg.value` to the `recipient`.
     * @dev Only callable by the `podOwner`'s EigenPod contract.
     */
    function createPayment(address podOwner, address recipient) external payable onlyEigenPod(podOwner) {
        uint224 paymentAmount = uint224(msg.value);
        if (paymentAmount != 0) {
            Payment memory payment = Payment({
                amount: paymentAmount,
                blockCreated: uint32(block.number)
            });
            _userPayments[recipient].payments.push(payment);
            emit PaymentCreated(podOwner, recipient, paymentAmount);
        }
    }

    /**
     * @notice Called in order to withdraw escrowed payments made to the `recipient` that have passed the `withdrawalDelayBlocks` period.
     * @param recipient The address to claim payments for.
     * @param maxNumberOfPaymentsToClaim Used to limit the maximum number of payments to loop through claiming.
     */
    function claimPayments(address recipient, uint256 maxNumberOfPaymentsToClaim) external nonReentrant onlyWhenNotPaused(PAUSED_PAYMENT_CLAIMS) {
        _claimPayments(recipient, maxNumberOfPaymentsToClaim);
    }

    /**
     * @notice Called in order to withdraw escrowed payments made to the caller that have passed the `withdrawalDelayBlocks` period.
     * @param maxNumberOfPaymentsToClaim Used to limit the maximum number of payments to loop through claiming.
     */
    function claimPayments(uint256 maxNumberOfPaymentsToClaim) external nonReentrant onlyWhenNotPaused(PAUSED_PAYMENT_CLAIMS) {
        _claimPayments(msg.sender, maxNumberOfPaymentsToClaim);
    }

    /// @notice Owner-only function for modifying the value of the `withdrawalDelayBlocks` variable.
    function setWithdrawalDelayBlocks(uint256 newValue) external onlyOwner {
        _setWithdrawalDelayBlocks(newValue);
    }

    /// @notice Getter function for the mapping `_userPayments`
    function userPayments(address user) external view returns (UserPayments memory) {
        return _userPayments[user];
    }

    /// @notice Getter function for fetching the payment at the `index`th entry from the `_userPayments[user].payments` array
    function userPaymentByIndex(address user, uint256 index) external view returns (Payment memory) {
        return _userPayments[user].payments[index];
    }

    /// @notice Getter function for fetching the length of the payments array of a specific user
    function userPaymentsLength(address user) external view returns (uint256) {
        return _userPayments[user].payments.length;
    }

    /// @notice Convenience function for checking whethere or not the payment at the `index`th entry from the `_userPayments[user].payments` array is currently claimable
    function canClaimPayment(address user, uint256 index) external view returns (bool) {
        return ((index >= _userPayments[user].paymentsCompleted) && (block.number >= _userPayments[user].payments[index].blockCreated + withdrawalDelayBlocks));
    }

    /// @notice internal function used in both of the overloaded `claimPayments` functions
    function _claimPayments(address recipient, uint256 maxNumberOfPaymentsToClaim) internal {
        uint256 amountToSend = 0;
        uint256 paymentsCompletedBefore = _userPayments[recipient].paymentsCompleted;
        uint256 _userPaymentsLength = _userPayments[recipient].payments.length;
        uint256 i = 0;
        while (i < maxNumberOfPaymentsToClaim && (paymentsCompletedBefore + i) < _userPaymentsLength) {
            // copy payment from storage to memory
            Payment memory payment = _userPayments[recipient].payments[paymentsCompletedBefore + i];
            // check if payment can be claimed. break the loop as soon as a payment cannot be claimed
            if (block.number < payment.blockCreated + withdrawalDelayBlocks) {
                break;
            }
            // otherwise, the payment can be claimed, in which case we increase the amountToSend and increment i
            amountToSend += payment.amount;
            // increment i to account for the payment being claimed
            unchecked {
                ++i;
            }
        }
        // mark the i payments as claimed
        _userPayments[recipient].paymentsCompleted = paymentsCompletedBefore + i;
        // actually send the ETH
        if (amountToSend != 0) {
            AddressUpgradeable.sendValue(payable(recipient), amountToSend);
        }
    }

    /// @notice internal function for changing the value of `withdrawalDelayBlocks`. Also performs sanity check and emits an event.
    function _setWithdrawalDelayBlocks(uint256 newValue) internal {
        require(newValue <= MAX_WITHDRAWAL_DELAY_BLOCKS, "EigenPodPaymentEscrow._setWithdrawalDelayBlocks: newValue too large");
        emit WithdrawalDelayBlocksSet(withdrawalDelayBlocks, newValue);
        withdrawalDelayBlocks = newValue;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __gap;
}