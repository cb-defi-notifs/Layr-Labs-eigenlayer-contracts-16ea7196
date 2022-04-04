// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../interfaces/IQueryManager.sol";
import "../../../interfaces/IDataLayrServiceManager.sol";
import "../../../interfaces/IDataLayr.sol";
import "../../../interfaces/IDataLayrVoteWeigher.sol";
import "../../../interfaces/IEigenLayrDelegation.sol";

abstract contract DataLayrServiceManagerStorage is IDataLayrServiceManager, IFeeManager {
    /**
     * @notice service fee that will be paid out by the disperser to the DataLayr nodes
     *         for storing per byte for per unit time. 
     */
    uint256 public feePerBytePerTime;

    /**
     * @notice challenge window for submitting fraudproof in case of incorrect payment 
     *         claim by the registered operator 
     */
    uint256 public constant paymentFraudProofInterval = 7 days;


    uint256 public paymentFraudProofCollateral = 1 wei;
    IDataLayr public dataLayr;
    IQueryManager public queryManager;
    //the DL vote weighter
    IDataLayrVoteWeigher public dlRegVW;

    /// @notice counter for number of assertions of data that has happened on this DataLayr
    uint48 public dumpNumber;

    /**
     * @notice mapping between the dumpNumber for a particular assertion of data into
     *         DataLayr and a compressed information on the signatures of the DataLayr 
     *         nodes who signed up to be the part of the quorum.  
     */
    mapping(uint64 => bytes32) public dumpNumberToSignatureHash;

    /**
     * @notice mapping between the total service fee that would be paid out in the 
     *         corresponding assertion of data into DataLayr 
     */
    mapping(uint64 => uint256) public dumpNumberToFee;


    /**
     * @notice mapping between the operator and its current committed or payment
     *         or the last redeemed payment 
     */
    mapping(address => Payment) public operatorToPayment;

    
    mapping(address => address) public operatorToPaymentChallenge;

    //a deposit root is posted every depositRootInterval dumps
    uint16 public constant depositRootInterval = 1008; //this is once a week if dumps every 10 mins
    mapping(uint256 => bytes32) public depositRoots; // blockNumber => depositRoot

    // Payment
    struct Payment {
        uint48 fromDumpNumber; // dumpNumber payment being claimed from
        uint48 toDumpNumber; // dumpNumber payment being claimed to exclusive
        // payment for range [fromDumpNumber, toDumpNumber)
        uint32 commitTime; // when commited, used for fraud proof period
        uint120 amount; // max 1.3e36, keep in mind for token decimals
        uint8 status; // 0: commited, 1: redeemed
        uint256 collateral; //account for if collateral changed
    }

    struct PaymentChallenge {
        address challenger;
        uint48 fromDumpNumber;
        uint48 toDumpNumber;
        uint120 amount1;
        uint120 amount2;
    }
}
