// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IRepository.sol";
import "../interfaces/IServiceManager.sol";
import "../interfaces/IQuorumRegistry.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IPaymentManager.sol";
import "./Repository.sol";
import "../permissions/RepositoryAccess.sol";

import "ds-test/test.sol";

/**
 @notice This contract is used for doing interactive payment challenge.
 */
 // contract is marked as abstract since it does not implement the `respondToPaymentChallengeFinal` function -- see DataLayrPaymentManager for an example
abstract contract PaymentManager is 
    RepositoryAccess, 
    IPaymentManager
    // ,DSTest 
    {
    using SafeERC20 for IERC20;
    /**********************
     DATA STRUCTURES
     **********************/

    /**
      @notice used for storing information on the most recent payment made to the operator
     */


    /**
     * @notice challenge window for submitting fraudproof in case of incorrect payment 
     *         claim by the registered operator 
     */
    uint256 public constant paymentFraudProofInterval = 7 days;

    /**
     @notice this is the payment that has to be made as a collateral for fraudproof 
             during payment challenges
     */
    uint256 public paymentFraudProofCollateral;

    /**
     * @notice the ERC20 token that will be used by the disperser to pay the service fees to
     *         middleware nodes.
     */
    IERC20 public immutable paymentToken;

    // collateral token used for placing collateral on challenges & payment commits
    IERC20 public immutable collateralToken;

    /**
     * @notice The EigenLayr delegation contract for this middleware which is primarily used by
     *      delegators to delegate their stake to operators who would serve as middleware
     *      nodes and so on.
     */
    /**
      @dev For more details, see EigenLayrDelegation.sol. 
     */
    IEigenLayrDelegation public immutable eigenLayrDelegation;

    /**
        @notice mapping between the operator and its current committed payment
        or last redeemed payment 
    */
    mapping(address => Payment) public operatorToPayment;

    // operator => PaymentChallenge
    mapping(address => PaymentChallenge) public operatorToPaymentChallenge;

    // deposits of future fees to be drawn against when paying for taking service for the task
    mapping(address => uint256) public depositsOf;

    // depositors => addresses approved to spend deposits => allowance
    mapping(address => mapping(address => uint256)) public allowances;

    /******** 
     EVENTS
     ********/
    event PaymentCommit(
        address operator,
        uint32 fromTaskNumber,
        uint32 toTaskNumber,
        uint256 fee
    );
    event PaymentRedemption(address indexed operator, uint256 fee);

    event PaymentBreakdown(address indexed operator, uint32 fromTaskNumber, uint32 toTaskNumber, uint120 amount1, uint120 amount2);

    event PaymentChallengeInit(address indexed operator, address challenger);

    event PaymentChallengeResolution(address indexed operator, bool operatorWon);



    constructor(
        IERC20 _paymentToken,
        uint256 _paymentFraudProofCollateral,
        IRepository _repository
    )   
        // set repository address equal to that of serviceManager
        RepositoryAccess(_repository) 
    {
        paymentToken = _paymentToken;
        paymentFraudProofCollateral = _paymentFraudProofCollateral;
        IServiceManager _serviceManager = _repository.serviceManager();
        collateralToken = _serviceManager.collateralToken();
        eigenLayrDelegation = _serviceManager.eigenLayrDelegation();
    }


    /**
     @notice deposit one-time fees by the middleware with this contract for set number of tasks 
     */
    /**
     @param onBehalfOf could be the msg.sender or someone lese who is depositing 
     this future fees           
     */ 
    function depositFutureFees(address onBehalfOf, uint256 amount) external {
        paymentToken.transferFrom(msg.sender, address(this), amount);
        depositsOf[onBehalfOf] += amount;
    }


    function setAllowance(address allowed, uint256 amount) public {
        allowances[msg.sender][allowed] = amount;
    }


    /**
     @notice Used for deducting the fees from the payer to the middleware
     */
    function payFee(address initiator, address payer, uint256 feeAmount) external onlyServiceManager {
        if (initiator != payer){
            if (allowances[payer][initiator] != type(uint256).max) {
                allowances[payer][initiator] -= feeAmount;
            }
        }

        // decrement `payer`'s stored deposits
        depositsOf[payer] -= feeAmount;
    }



    function setPaymentFraudProofCollateral(
        uint256 _paymentFraudProofCollateral
    ) public onlyRepositoryGovernance {
        paymentFraudProofCollateral = _paymentFraudProofCollateral;
    }

    /**
     @notice This is used by an operator to make claim on the  amount that they deserve 
             for their service since their last payment until toTaskNumber  
     */
    function commitPayment(uint32 toTaskNumber, uint120 amount) external {
        IQuorumRegistry registry = IQuorumRegistry(address(repository.registry()));

        // only registered operators can call
        require(
            registry.isRegistered(msg.sender),
            "PaymentManager.commitPayment: Only registered operators can call this function"
        );

        require(toTaskNumber <= taskNumber(), "PaymentManager.commitPayment: Cannot claim future payments");

        // can only claim for a payment after redeeming the last payment
        require(
            operatorToPayment[msg.sender].status == PaymentStatus.REDEEMED,
            "PaymentManager.commitPayment: Require last payment is redeemed"
        );

        // operator puts up collateral which can be slashed in case of wrongful payment claim
        collateralToken.transferFrom(
            msg.sender,
            address(this),
            paymentFraudProofCollateral
        );

        /********************
         recording payment claims for the operator
         ********************/

        uint32 fromTaskNumber;

        // calculate the UTC timestamp at which the payment claim will be optimistically confirmed
        uint32 confirmAt = uint32(block.timestamp + paymentFraudProofInterval);



        // for the special case of this being the first payment that is being claimed by the operator;
        /**
         @notice this special case also implies that the operator must be claiming payment from 
                 when the operator registered.   
         */
        if (operatorToPayment[msg.sender].fromTaskNumber == 0) {
            // get the taskNumber when the operator registered
            fromTaskNumber = registry.getFromTaskNumberForOperator(msg.sender);

        } else {
            // you have to redeem starting from the last task you previously redeemed up to
            fromTaskNumber = operatorToPayment[msg.sender].toTaskNumber;
        }

        require(fromTaskNumber < toTaskNumber, "invalid payment range");

        // update the record for the commitment to payment made by the operator
        operatorToPayment[msg.sender] = Payment(
            fromTaskNumber,
            toTaskNumber,
            confirmAt,
            amount,
            // set payment status as 1: committed
            PaymentStatus.COMMITTED,
            // storing collateral amount deposited
            paymentFraudProofCollateral
        );

        emit PaymentCommit(msg.sender, fromTaskNumber, toTaskNumber, amount);
    }

    /**
     @notice This function can only be called after the challenge window for the payment claim has completed.
     */
    function redeemPayment() external {
        require(operatorToPayment[msg.sender].status == PaymentStatus.COMMITTED,
            "PaymentManager.redeemPayment: Payment Status is not 'COMMITTED'"
        );

        require(
            block.timestamp > operatorToPayment[msg.sender].confirmAt,
            "PaymentManager.redeemPayment: Payment still eligible for fraud proof"
        );

        // update the status to show that operator's payment is getting redeemed
        operatorToPayment[msg.sender].status = PaymentStatus.REDEEMED;

        // transfer back the collateral to the operator as there was no successful
        // challenge to the payment commitment made by the operator.
        collateralToken.transfer(
            msg.sender,
            operatorToPayment[msg.sender].collateral
        );

        ///look up payment amount and delegation terms address for the msg.sender
        uint256 amount = operatorToPayment[msg.sender].amount;

        IDelegationTerms dt = eigenLayrDelegation.delegationTerms(msg.sender);
        // transfer the amount due in the payment claim of the operator to its delegation
        // terms contract, where the delegators can withdraw their rewards.
        paymentToken.transfer(address(dt), amount);

// TODO: make this a low-level call with gas budget that ignores reverts
        // inform the DelegationTerms contract of the payment, which will determine
        // the rewards operator and its delegators are eligible for
        dt.payForService(paymentToken, amount);

        emit PaymentRedemption(msg.sender, amount);
    }

    /**
    @notice This function would be called by a fraud prover to challenge a payment 
             by initiating an interactive type proof
     **/
    /**
     @param operator is the operator against whose payment claim the fraud proof is being made
     @param amount1 is the reward amount the challenger in that round claims is for the first half of tasks
     @param amount2 is the reward amount the challenger in that round claims is for the second half of tasks
     **/
    function challengePaymentInit(
        address operator,
        uint120 amount1,
        uint120 amount2
    ) external {
        
        require(
            block.timestamp < operatorToPayment[operator].confirmAt 
                &&
                operatorToPayment[operator].status == PaymentStatus.COMMITTED,
            "PaymentManager.challengePaymentInit: Fraudproof interval has passed for payment"
        );

        // store challenge details
        operatorToPaymentChallenge[operator] = PaymentChallenge(
                operator,
                msg.sender,
                address(repository.serviceManager()),
                operatorToPayment[operator].fromTaskNumber,
                operatorToPayment[operator].toTaskNumber,
                amount1,
                amount2,
                // recording current timestamp plus the fraudproof interval as the `settleAt` timestamp for this challenge
                uint32(block.timestamp + paymentFraudProofInterval),
                // set the status for the operator to respond next
                ChallengeStatus.OPERATOR_TURN
        );

        //move collateral over
        uint256 collateral = operatorToPayment[operator].collateral;
        collateralToken.transferFrom(msg.sender, address(this), collateral);
        // update the payment status and reset the fraudproof window for this payment
        operatorToPayment[operator].status = PaymentStatus.CHALLENGED;
        operatorToPayment[operator].confirmAt = uint32(block.timestamp + paymentFraudProofInterval);
        emit PaymentChallengeInit(operator, msg.sender);
    }


    //challenger challenges a particular half of the payment
    function challengePaymentHalf(
        address operator,
        bool secondHalf,
        uint120 amount1,
        uint120 amount2
    ) external {
        // copy challenge struct to memory
        PaymentChallenge memory challenge = operatorToPaymentChallenge[operator];

        ChallengeStatus status = challenge.status;

        require(
            (status == ChallengeStatus.CHALLENGER_TURN && challenge.challenger == msg.sender) ||
                (status == ChallengeStatus.OPERATOR_TURN && challenge.operator == msg.sender),
            "PaymentManager.challengePaymentHalf: Must be challenger and their turn or operator and their turn"
        );

        require(
            block.timestamp < challenge.settleAt,
            "PaymentManager.challengePaymentHalf: Challenge has already settled"
        );


        uint32 fromTaskNumber = challenge.fromTaskNumber;
        uint32 toTaskNumber = challenge.toTaskNumber;
        uint32 diff;

        //change interval to the one challenger cares about
        // if the difference between the current start and end is even, the new interval has an endpoint halfway inbetween
        // if the difference is odd = 2n + 1, the new interval has a "from" endpoint at (start + n = end - (n + 1)) if the second half is challenged,
        //  or a "to" endpoint at (end - (2n + 2)/2 = end - (n + 1) = start + n) if the first half is challenged
        if (secondHalf) {
            diff = (toTaskNumber - fromTaskNumber) / 2;
            challenge.fromTaskNumber = fromTaskNumber + diff;
            //if next step is not final
            _updateStatus(operator, diff);

            _updateChallengeAmounts(operator, DissectionType.SECOND_HALF, amount1, amount2);
        } else {
            diff = (toTaskNumber - fromTaskNumber);
            if (diff % 2 == 1) {
                diff += 1;
            }
            diff /= 2;
            challenge.toTaskNumber = toTaskNumber - diff;

            _updateStatus(operator, diff);

            _updateChallengeAmounts(operator, DissectionType.FIRST_HALF, amount1, amount2);
        }

        // extend the settlement time for the challenge, giving the next participant in the interactive fraudproof `paymentFraudProofInterval` to respond
        challenge.settleAt = uint32(block.timestamp + paymentFraudProofInterval);

        // update challenge struct in storage
        operatorToPaymentChallenge[operator] = challenge;
        
        // TODO: should this event reflect anything about whose turn is next (challenger vs. operator?)
        emit PaymentBreakdown(operator, challenge.fromTaskNumber, challenge.toTaskNumber, challenge.amount1, challenge.amount2);
    }



// TODO: change this function to just modify a 'PaymentChallenge' in memory, rather than write to storage? (might save gas)
    /**
     @notice This function is used for updating the status of the challenge in terms of who
             has to respond to the interactive challenge mechanism next -  is it going to be
             challenger or the operator.   
     */
    /**
     @param operator is the operator whose payment claim is being challenged
     @param diff is the number of tasks across which payment is being challenged in this iteration
     */ 
    function _updateStatus(address operator, uint32 diff)
        internal
        returns (bool)
    {
        // payment challenge for one task
        if (diff == 1) {
            //set to one step turn of either challenger or operator
            operatorToPaymentChallenge[operator].status = msg.sender == operator ? ChallengeStatus.CHALLENGER_TURN_ONE_STEP : ChallengeStatus.OPERATOR_TURN_ONE_STEP;
            return false;

        // payment challenge across more than one task
        } else {
            // set to dissection turn of either challenger or operator
            operatorToPaymentChallenge[operator].status = msg.sender == operator ? ChallengeStatus.CHALLENGER_TURN : ChallengeStatus.OPERATOR_TURN;
            return true;
        }
   }


// TODO: change this function to just modify a 'PaymentChallenge' in memory, rather than write to storage? (might save gas)
    //an operator can respond to challenges and breakdown the amount
    // used to update challenge amounts when the operator (or challenger) breaks down the challenged amount (single bisection step)
    function _updateChallengeAmounts(
        address operator, 
        DissectionType dissectionType,
        uint120 amount1,
        uint120 amount2
    ) internal {
        if (dissectionType == DissectionType.FIRST_HALF) {
            //if first half is challenged, break the first half of the payment into two halves
            require(
                amount1 + amount2 != operatorToPaymentChallenge[operator].amount1,
                "PaymentManager._updateChallengeAmounts: Invalid amount breakdown"
            );
        } else if (dissectionType == DissectionType.SECOND_HALF) {
            //if second half is challenged, break the second half of the payment into two halves
            require(
                amount1 + amount2 != operatorToPaymentChallenge[operator].amount2,
                "PaymentManager._updateChallengeAmounts: Invalid amount breakdown"
            );
        } else {
            revert("PaymentManager._updateChallengeAmounts: invalid DissectionType");
        }
        // update the stored payment halves
        operatorToPaymentChallenge[operator].amount1 = amount1;
        operatorToPaymentChallenge[operator].amount2 = amount2;
    }

    function resolveChallenge(address operator) external {
        // copy challenge struct to memory
        PaymentChallenge memory challenge = operatorToPaymentChallenge[operator];

        require(
            block.timestamp > challenge.settleAt,
            "PaymentManager.resolveChallenge: challenge has not yet reached settlement time"
        );
        ChallengeStatus status = challenge.status;
        // if operator did not respond
        if (status == ChallengeStatus.OPERATOR_TURN || status == ChallengeStatus.OPERATOR_TURN_ONE_STEP) {
            _resolve(challenge, challenge.challenger);
        // if challenger did not respond
        } else if (status == ChallengeStatus.CHALLENGER_TURN || status == ChallengeStatus.CHALLENGER_TURN_ONE_STEP) {
            _resolve(challenge, challenge.operator);
        }
    }

    /* 
    @notice: resolve payment challenge
    
    @param winner is the party who wins the challenge, either the challenger or the operator
    @param operatorSuccessful is true when the operator wins the challenge agains the challenger
    */
    function _resolve(PaymentChallenge memory challenge, address winner) internal {
        address operator = challenge.operator;
        address challenger = challenge.challenger;
        if (winner == operator) {
            // operator was correct, allow for another challenge
            operatorToPayment[operator].status = PaymentStatus.COMMITTED;
            operatorToPayment[operator].confirmAt = uint32(block.timestamp + paymentFraudProofInterval);
            /*
            * Since the operator hasn't been proved right (only challenger has been proved wrong)
            * transfer them only challengers collateral, not their own collateral (which is still
            * locked up in this contract)
             */
            collateralToken.safeTransfer(
                operator,
                operatorToPayment[operator].collateral
            );
            emit PaymentChallengeResolution(operator, true);
        } else {
            // challeger was correct, reset payment
            operatorToPayment[operator].status = PaymentStatus.REDEEMED;
            //give them their collateral and the operator's
            collateralToken.safeTransfer(
                challenger,
                2 * operatorToPayment[operator].collateral
            );
            emit PaymentChallengeResolution(operator, false);
        }
    }

    function getChallengeStatus(address operator) external view returns(ChallengeStatus) {
        return operatorToPaymentChallenge[operator].status;
    }


    function getAmount1(address operator) external view returns (uint120) {
        return operatorToPaymentChallenge[operator].amount1;
    }

    function getAmount2(address operator) external view returns (uint120) {
        return operatorToPaymentChallenge[operator].amount2;
    }

    function getToTaskNumber(address operator) external view returns (uint48) {
        return operatorToPaymentChallenge[operator].toTaskNumber;
    }

    function getFromTaskNumber(address operator) external view returns (uint48) {
        return operatorToPaymentChallenge[operator].fromTaskNumber;
    }

    function getDiff(address operator) external view returns (uint48) {
        return operatorToPaymentChallenge[operator].toTaskNumber - operatorToPaymentChallenge[operator].fromTaskNumber;
    }

    function getPaymentCollateral(address operator)
        public
        view
        returns (uint256)
    {
        return operatorToPayment[operator].collateral;
    }

    function taskNumber() internal view returns (uint32) {
        return repository.serviceManager().taskNumber();
    }
}
