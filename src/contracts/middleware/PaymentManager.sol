// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IRepository.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IProofOfStakingOracle.sol";
import "../interfaces/IDelegationTerms.sol";
import "./ServiceManagerBase.sol";
import "./SignatureChecker.sol";
import "../libraries/BytesLib.sol";
import "../libraries/Merkle.sol";
import "./Repository.sol";
import "ds-test/test.sol";

/**
 * @notice This contract is used for:
            - initializing the data store by the disperser
            - confirming the data store by the disperser with inferred aggregated signatures of the quorum
            - doing forced disclosure challenge
            - doing payment challenge
 */
contract PaymentManager is SignatureChecker {
    using BytesLib for bytes;
    /**
     * @notice The EigenLayr delegation contract for this middleware which is primarily used by
     *      delegators to delegate their stake to operators who would serve as
     *      nodes and so on.
     */
    /**
      @dev For more details, see EigenLayrDelegation.sol. 
     */
    IEigenLayrDelegation public immutable eigenLayrDelegation;

    /**
     * @notice factory contract used to deploy new PaymentChallenge contracts
     */
    PaymentChallengeFactory public immutable paymentChallengeFactory;

    // EVENTS
    event PaymentCommit(
        address operator,
        uint32 fromTaskNumber,
        uint32 toTaskNumber,
        uint256 fee
    );

    event PaymentChallengeInit(address operator, address challenger);

    event PaymentChallengeResolution(address operator, bool operatorWon);

    event PaymentRedemption(address operator, uint256 fee);

    constructor(
        IEigenLayrDelegation _eigenLayrDelegation,
        IERC20 _paymentToken,
        IERC20 _collateralToken,
        IRepository _repository,
        PaymentChallengeFactory _paymentChallengeFactory
    ) ServiceManagerBase(_paymentToken, _collateralToken, _repository) {
        eigenLayrDelegation = _eigenLayrDelegation;
        paymentChallengeFactory = _paymentChallengeFactory;
        
    }

    /**
     @notice This is used by a  operator to make claim on the @param amount that they deserve 
             for their service since their last payment until @param toTaskNumber  
     **/
    function commitPayment(uint32 toTaskNumber, uint120 amount) external {
        IRegistry registry = IRegistry(
            address(repository.voteWeigher())
        );

        // only registered  operators can call
        require(
            registry.getOperatorType(msg.sender) != 0,
            "Only registered operators can call this function"
        );

        require(toTaskNumber <= taskNumber, "Cannot claim future payments");

        // operator puts up collateral which can be slashed in case of wrongful payment claim
        collateralToken.transferFrom(
            msg.sender,
            address(this),
            paymentFraudProofCollateral
        );

        /**
         @notice recording payment claims for the  operators
         */
        uint32 fromTaskNumber;

        // for the special case of this being the first payment that is being claimed by the  operator;
        /**
         @notice this special case also implies that the  operator must be claiming payment from 
                 when the operator registered.   
         */
        if (operatorToPayment[msg.sender].fromTaskNumber == 0) {
            // get the taskNumber when the  operator registered
            fromTaskNumber = registry.getOperatorFromTaskNumber(msg.sender);

            require(fromTaskNumber < toTaskNumber, "invalid payment range");

            // record the payment information pertaining to the operator
            operatorToPayment[msg.sender] = Payment(
                fromTaskNumber,
                toTaskNumber,
                uint32(block.timestamp),
                amount,
                // setting to 0 to indicate commitment to payment claim
                0,
                paymentFraudProofCollateral
            );

            return;
        }

        // can only claim for a payment after redeeming the last payment
        require(
            operatorToPayment[msg.sender].status == 1,
            "Require last payment is redeemed"
        );

        // you have to redeem starting from the last time redeemed up to
        fromTaskNumber = operatorToPayment[msg.sender].toTaskNumber;

        require(fromTaskNumber < toTaskNumber, "invalid payment range");

        // update the record for the commitment to payment made by the operator
        operatorToPayment[msg.sender] = Payment(
            fromTaskNumber,
            toTaskNumber,
            uint32(block.timestamp),
            amount,
            0,
            paymentFraudProofCollateral
        );

        emit PaymentCommit(msg.sender, fromTaskNumber, toTaskNumber, amount);
    }

    /**
     @notice This function can only be called after the challenge window for the payment claim has completed.
     */
    function redeemPayment() external {
        require(
            block.timestamp >
                operatorToPayment[msg.sender].commitTime +
                    paymentFraudProofInterval &&
                operatorToPayment[msg.sender].status == 0,
            "Still eligible for fraud proofs"
        );

        // update the status to show that operator's payment is getting redeemed
        operatorToPayment[msg.sender].status = 1;

        // transfer back the collateral to the operator as there was no successful
        // challenge to the payment commitment made by the operator.
        collateralToken.transfer(
            msg.sender,
            operatorToPayment[msg.sender].collateral
        );

        ///look up payment amount and delegation terms address for the msg.sender
        uint256 amount = operatorToPayment[msg.sender].amount;
        IDelegationTerms dt = eigenLayrDelegation.delegationTerms(msg.sender);

        // i.e. if operator is not a 'self operator'
        if (address(dt) != address(0)) {
            // transfer the amount due in the payment claim of the operator to its delegation
            // terms contract, where the delegators can withdraw their rewards.
            paymentToken.transfer(address(dt), amount);

            // inform the DelegationTerms contract of the payment, which would determine
            // the rewards operator and its delegators are eligible for
            dt.payForService(paymentToken, amount);

            // i.e. if the operator *is* a 'self operator'
        } else {
            //simply transfer the payment amount in this case
            paymentToken.transfer(msg.sender, amount);
        }

        emit PaymentRedemption(msg.sender, amount);
    }

    function setPaymentFraudProofCollateral(
        uint256 _paymentFraudProofCollateral
    ) public onlyRepositoryGovernance {
        paymentFraudProofCollateral = _paymentFraudProofCollateral;
    }
}
