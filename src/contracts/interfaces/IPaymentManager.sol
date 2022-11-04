// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Interface for a `PaymentManager` contract.
 * @author Layr Labs, Inc.
 */
interface IPaymentManager {
    enum DissectionType {
        INVALID,
        FIRST_HALF,
        SECOND_HALF
    }
    enum PaymentStatus {
        REDEEMED,
        COMMITTED,
        CHALLENGED
    }
    enum ChallengeStatus {
        RESOLVED,
        OPERATOR_TURN,
        CHALLENGER_TURN,
        OPERATOR_TURN_ONE_STEP,
        CHALLENGER_TURN_ONE_STEP
    }

    /**
     * @notice used for storing information on the most recent payment made to the operator
     */
    struct Payment {
        // taskNumber starting from which payment is being claimed
        uint32 fromTaskNumber;
        // taskNumber until which payment is being claimed (exclusive)
        uint32 toTaskNumber;
        // recording when the payment will optimistically be confirmed; used for fraudproof period
        uint32 confirmAt;
        // payment for range [fromTaskNumber, toTaskNumber)
        /// @dev max 1.3e36, keep in mind for token decimals
        uint96 amount;
        /**
         * @notice The possible statuses are:
         * - 0: REDEEMED,
         * - 1: COMMITTED,
         * - 2: CHALLENGED
         */
        PaymentStatus status;
        uint256 collateral; //account for if collateral changed
    }

    /**
     * @notice used for storing information on the payment challenge as part of the interactive process
     */
    struct PaymentChallenge {
        // operator whose payment claim is being challenged,
        address operator;
        // the entity challenging with the fraudproof
        address challenger;
        // address of the service manager contract
        address serviceManager;
        // the TaskNumber from which payment has been computed
        uint32 fromTaskNumber;
        // the TaskNumber until which payment has been computed to
        uint32 toTaskNumber;
        // reward amount the challenger claims is for the first half of tasks
        uint96 amount1;
        // reward amount the challenger claims is for the second half of tasks
        uint96 amount2;
        // used for recording the time when challenge was created
        uint32 settleAt; // when committed, used for fraudproof period
        // indicates the status of the challenge
        /**
         * @notice The possible statuses are:
         * - 0: RESOLVED,
         * - 1: operator turn (dissection),
         * - 2: challenger turn (dissection),
         * - 3: operator turn (one step),
         * - 4: challenger turn (one step)
         */
        ChallengeStatus status;
    }

    struct TotalStakes {
        uint256 signedStakeFirstQuorum;
        uint256 signedStakeSecondQuorum;
    }

    function depositFutureFees(address onBehalfOf, uint256 amount) external;

    function setAllowance(address allowed, uint256 amount) external;

    function payFee(address initiator, address payer, uint256 feeAmount) external;

    function setPaymentFraudproofCollateral(uint256 _paymentFraudproofCollateral) external;

    function commitPayment(uint32 toTaskNumber, uint96 amount) external;

    function redeemPayment() external;

    function paymentFraudproofInterval() external view returns (uint256);

    function paymentFraudproofCollateral() external view returns (uint256);

    function getPaymentCollateral(address) external view returns (uint256);

    function paymentToken() external view returns (IERC20);

    function collateralToken() external view returns (IERC20);

    function getChallengeStatus(address operator) external view returns (ChallengeStatus);

    function initPaymentChallenge(address operator, uint96 amount1, uint96 amount2) external;

    function performChallengeBisectionStep(address operator, bool secondHalf, uint96 amount1, uint96 amount2)
        external;

    function resolveChallenge(address operator) external;

    function getAmount1(address operator) external view returns (uint96);

    function getAmount2(address operator) external view returns (uint96);

    function getToTaskNumber(address operator) external view returns (uint48);

    function getFromTaskNumber(address operator) external view returns (uint48);

    function getDiff(address operator) external view returns (uint48);
}
