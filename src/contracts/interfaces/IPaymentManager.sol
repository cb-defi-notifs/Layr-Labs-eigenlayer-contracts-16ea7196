// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IRepositoryAccess.sol";

// TODO: provide more functions for this spec
interface IPaymentManager is IRepositoryAccess {
    enum DissectionType {
        INVALID,
        FIRST_HALF,
        SECOND_HALF
    }
    enum PaymentStatus{ 
        REDEEMED,
        COMMITTED,
        CHALLENGED
    }
    enum ChallengeStatus{ 
        RESOLVED,
        OPERATOR_TURN, 
        CHALLENGER_TURN, 
        OPERATOR_TURN_ONE_STEP, 
        CHALLENGER_TURN_ONE_STEP
    }	   

    /**
      @notice used for storing information on the most recent payment made to the operator
     */
    struct Payment {
        // taskNumber starting from which payment is being claimed 
        uint32 fromTaskNumber; 

        // taskNumber until which payment is being claimed (exclusive) 
        uint32 toTaskNumber; 

        // recording when the payment will optimistically be confirmed; used for fraud proof period
        uint32 confirmAt; 

        // payment for range [fromTaskNumber, toTaskNumber)
        /// @dev max 1.3e36, keep in mind for token decimals
        uint120 amount; 

        /**
         @notice The possible statuses are:
                    - 0: REDEEMED,
                    - 1: COMMITTED,
                    - 2: CHALLENGED
         */

        PaymentStatus status;

        uint256 collateral; //account for if collateral changed
    }

    /**
      @notice used for storing information on the payment challenge as part of the interactive process
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
        uint120 amount1;

        // reward amount the challenger claims is for the second half of tasks
        uint120 amount2;

        // used for recording the time when challenge was created
        uint32 settleAt; // when committed, used for fraud proof period

        // indicates the status of the challenge
        /**
         @notice The possible statuses are:
                    - 0: RESOLVED,
                    - 1: operator turn (dissection),
                    - 2: challenger turn (dissection),
                    - 3: operator turn (one step),
                    - 4: challenger turn (one step)
         */
        ChallengeStatus status;   
    }


    struct TotalStakes {
        uint256 ethStakeSigned;
        uint256 eigenStakeSigned;
    }

    function paymentFraudProofInterval() external view returns (uint256);

    function paymentFraudProofCollateral() external view returns (uint256);

    function getPaymentCollateral(address) external view returns (uint256);

    function paymentToken() external view returns(IERC20);

    function collateralToken() external view returns(IERC20);
    
    function depositFutureFees(address onBehalfOf, uint256 amount) external;

}