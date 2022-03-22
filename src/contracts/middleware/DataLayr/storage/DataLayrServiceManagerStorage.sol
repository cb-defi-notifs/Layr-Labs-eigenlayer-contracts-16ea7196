// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../../interfaces/IERC20.sol";
import "../../../interfaces/IQueryManager.sol";
import "../../../interfaces/DataLayrInterfaces.sol";
import "../../../interfaces/IEigenLayrDelegation.sol";

abstract contract DataLayrServiceManagerStorage is IDataLayrServiceManager, IFeeManager {
    uint256 public feePerBytePerTime;
    uint256 public constant paymentFraudProofInterval = 7 days;
    uint256 public paymentFraudProofCollateral = 1 wei;
    IDataLayr public dataLayr;
    IQueryManager public queryManager;
    uint48 public dumpNumber;
    mapping(uint64 => bytes32) public dumpNumberToSignatureHash;
    mapping(uint64 => uint256) public dumpNumberToFee;
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
