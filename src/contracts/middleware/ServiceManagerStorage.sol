// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IRepository.sol";
import "../interfaces/IGeneralServiceManager.sol";
import "../interfaces/IRegistry.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "./PaymentChallengeFactory.sol";

abstract contract ServiceManagerStorage is IGeneralServiceManager {
    
    // DATA STRUCTURE

    /**
     @notice used for storing information on the most recent payment made to the operator
     */
    struct Payment {
        // taskNumber starting from which payment is being claimed 
        uint32 fromTaskNumber; 

        // taskNumber until which payment is being claimed (exclusive) 
        uint32 toTaskNumber; 

        // recording when committment for payment made; used for fraud proof period
        uint32 commitTime; 

        // payment for range [fromTaskNumber, toTaskNumber)
        /// @dev max 1.3e36, keep in mind for token decimals
        uint120 amount; 


        uint8 status; // 0: commited, 1: redeemed
        uint256 collateral; //account for if collateral changed
    }

    struct PaymentChallenge {
        address challenger;
        uint32 fromTaskNumber;
        uint32 toTaskNumber;
        uint120 amount1;
        uint120 amount2;
    }

    /**
     * @notice the ERC20 token that will be used by the disperser to pay the service fees to
     *         nodes.
     */
    IERC20 public immutable paymentToken;

    IERC20 public immutable collateralToken;

    IRepository public repository;

    /**
     * @notice service fee that will be paid out by the disperser to the nodes
     *         for storing per byte for per unit time. 
     */
    uint256 public feePerBytePerTime;

    /**
     * @notice challenge window for submitting fraudproof in case of incorrect payment 
     *         claim by the registered operator 
     */
    uint256 public constant paymentFraudProofInterval = 7 days;


    /**
     @notice this is the payment that has to be made as a collateral for fraudproof 
             during payment challenges
     */
    uint256 public paymentFraudProofCollateral = 1 wei;


    /// @notice counter for number of assertions of data that has happened on this middleware
    uint32 public taskNumber = 1;

    /**
     * @notice mapping between the taskNumber for a particular assertion 
     *         and a compressed information on the signatures of the 
     *         nodes who signed up to be the part of the quorum.  
     */
    mapping(uint32 => bytes32) public taskNumberToSignatureHash;

    /**
     * @notice mapping between the total service fee that would be paid out in the 
     *         corresponding assertion
     */
    mapping(uint32 => uint256) public taskNumberToFee;

    /**
     * @notice mapping between the operator and its current committed or payment
     *         or the last redeemed payment 
     */
    mapping(address => Payment) public operatorToPayment;

    mapping(address => address) public operatorToPaymentChallenge;
 
    constructor(IERC20 _paymentToken, IERC20 _collateralToken) {
        paymentToken = _paymentToken;
        collateralToken = _collateralToken;
    }
}
