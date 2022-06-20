// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


import "./DataLayrPaymentChallengeFactory.sol";
import "ds-test/test.sol";

/**
@notice This contract is used for initalizing payment challenges and resolving them.
 */


 contract DataLayrPaymentChallengeManager  is DSTest {

     /**
    @notice used for storing information on the most recent payment made to the DataLayr operator
    */

    struct Payment {
        // dumpNumber starting from which payment is being claimed 
        uint32 fromDumpNumber; 
        // dumpNumber until which payment is being claimed (exclusive) 
        uint32 toDumpNumber; 
        // recording when committment for payment made; used for fraud proof period
        uint32 commitTime; 
        // payment for range [fromDumpNumber, toDumpNumber)
        /// @dev max 1.3e36, keep in mind for token decimals
        uint120 amount; 
        uint8 status; // 0: commited, 1: redeemed
        uint256 collateral; //account for if collateral changed
    }

    /*
        * @notice mapping between the operator and its current committed or payment
        *  or the last redeemed payment 
    */
    mapping(address => Payment) operatorToPayment;
    mapping(address => address) public operatorToPaymentChallenge;

    IERC20 public immutable collateralToken;
    address dlsmAddr;

    DataLayrPaymentChallengeFactory public dataLayrPaymentChallengeFactory;




    event PaymentChallengeInit(address operator, address challenger);
    event PaymentChallengeResolution(address operator, bool operatorWon);
    event PaymentRedemption(address operator, uint256 fee);

    uint256 public constant paymentFraudProofInterval = 7 days;



    constructor(
        IERC20 _collateralToken,
        address _dlsmAddr
    ){
        collateralToken = _collateralToken;
        dlsmAddr = _dlsmAddr;
        dataLayrPaymentChallengeFactory = new DataLayrPaymentChallengeFactory();
    }


    /**
    @notice This function would be called by a fraud prover to challenge a payment 
             by initiating an interactive type proof
     **/
    /**
     @param operator is the DataLayr operator against whose payment claim the fraud proof is being made
     @param amount1 is the reward amount the challenger in that round claims is for the first half of dumps
     @param amount2 is the reward amount the challenger in that round claims is for the second half of dumps
     **/
    function challengePaymentInit(
        address operator,
        uint120 amount1,
        uint120 amount2
    ) external {
        
        require(
            block.timestamp <
                operatorToPayment[operator].commitTime +
                    paymentFraudProofInterval &&
                operatorToPayment[operator].status == 0,
            "Fraud proof interval has passed"
        );
        
        // deploy new challenge contract
        address challengeContract = dataLayrPaymentChallengeFactory
            .createDataLayrPaymentChallenge(
                operator,
                msg.sender,
                dlsmAddr,
                address(this),
                operatorToPayment[operator].fromDumpNumber,
                operatorToPayment[operator].toDumpNumber,
                amount1,
                amount2
            );
        
        //move collateral over
        uint256 collateral = operatorToPayment[operator].collateral;
        collateralToken.transferFrom(msg.sender, address(this), collateral);
        //update payment
        operatorToPayment[operator].status = 2;
        operatorToPayment[operator].commitTime = uint32(block.timestamp);
        operatorToPaymentChallenge[operator] = challengeContract;
        emit PaymentChallengeInit(operator, msg.sender);
    }



    /*
    @notice: resolve payment challenge
    */
    function resolvePaymentChallenge(address operator, bool winner) external {
        require(
            msg.sender == operatorToPaymentChallenge[operator],
            "Only the payment challenge contract can call"
        );
        if (winner) {
            // operator was correct, allow for another challenge
            operatorToPayment[operator].status = 0;
            operatorToPayment[operator].commitTime = uint32(block.timestamp);
            //give them previous challengers collateral
            collateralToken.transfer(
                operator,
                operatorToPayment[operator].collateral
            );
            emit PaymentChallengeResolution(operator, true);
        } else {
            // challeger was correct, reset payment
            operatorToPayment[operator].status = 1;
            //give them their collateral and the operators
            collateralToken.transfer(
                operator,
                2 * operatorToPayment[operator].collateral
            );
            emit PaymentChallengeResolution(operator, false);
        }
    }


 }