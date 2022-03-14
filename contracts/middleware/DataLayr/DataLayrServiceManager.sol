// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IQueryManager.sol";
import "../../interfaces/DataLayrInterfaces.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "DataLayrPaymentChallenge.sol";
import "../QueryManager.sol";

contract DataLayrServiceManager is IFeeManager, IDataLayrServiceManager {
    IEigenLayrDelegation public immutable eigenLayrDelegation;
    uint256 public feePerBytePerTime;
    uint256 public constant paymentFraudProofInterval = 7 days;
    uint256 public paymentFraudProofCollateral = 1 wei;
    IDataLayr public dataLayr;
    IERC20 public immutable paymentToken;
    IQueryManager public queryManager;
    uint48 public dumpNumber;
    mapping(uint64 => bytes32) public dumpNumberToSignatureHash;
    mapping(uint64 => uint256) public dumpNumberToFee;
    mapping(address => Payment) public operatorToPayment;
    mapping(address => address) public operatorToPaymentChallenge;

    // Payment
    struct Payment {
        uint48 fromDumpNumber; // dumpNumber payment being claimed from
        uint48 toDumpNumber; // dumpNumber payment being claimed to exclusive
        // payment for range [fromDumpNumber, toDumpNumber)
        uint32 commitTime; // when commited, used for fraud proof period
        uint120 amount; // max 1.3e36, keep in mind for token decimals
        uint8 status; // 0: commited, 1: redeemed
    }

    struct PaymentChallenge {
        address challenger;
        uint48 fromDumpNumber;
        uint48 toDumpNumber;
        uint120 amount1;
        uint120 amount2;
    }

    constructor(IEigenLayrDelegation _eigenLayrDelegation, IERC20 _paymentToken)
    {
        eigenLayrDelegation = _eigenLayrDelegation;
        paymentToken = _paymentToken;
    }

    function setQueryManager(IQueryManager _queryManager) public {
        require(
            address(queryManager) == address(0),
            "Query Manager already set"
        );
        queryManager = _queryManager;
    }

    function setFeePerBytePerTime(uint256 _feePerBytePerTime) public {
        require(
            address(queryManager) == msg.sender,
            "Query Manager can only change stake"
        );
        feePerBytePerTime = _feePerBytePerTime;
    }

    function setPaymentFraudProofCollateral(
        uint256 _paymentFraudProofCollateral
    ) public {
        require(
            address(queryManager) == msg.sender,
            "Query Manager can only change stake"
        );
        paymentFraudProofCollateral = _paymentFraudProofCollateral;
    }

    //pays fees for a datastore leaving tha payment in this contract and calling the datalayr contract with needed information
    function payFeeForDataStore(
        bytes32 ferkleRoot,
        uint32 totalBytes,
        uint32 storePeriodLength,
        address submitter,
        uint24 quorum
    ) external payable {
        require(
            msg.sender == address(queryManager),
            "Only the query manager can call this function"
        );
        require(storePeriodLength < 604800, "store for less than 7 days");
        // fees as a function of bytes of data and time to store it
        uint256 fee = totalBytes * storePeriodLength * feePerBytePerTime;
        dumpNumber++;
        dumpNumberToFee[dumpNumber] = fee;
        IDataLayrVoteWeigher(address(queryManager.voteWeighter()))
            .setLatestTime(uint32(block.timestamp) + storePeriodLength);
        //get fees
        paymentToken.transferFrom(msg.sender, address(this), fee);
        // call DL contract
        dataLayr.initDataStore(
            dumpNumber,
            ferkleRoot,
            totalBytes,
            storePeriodLength,
            submitter,
            quorum
        );
    }

    //pays fees for a datastore leaving tha payment in this contract and calling the datalayr contract with needed information
    function confirmDump(
        uint48 dumpNumberToConfirm,
        bytes32 ferkleRoot,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        uint8[] calldata vs
    ) external payable {
        require(
            msg.sender == address(queryManager),
            "Only the query manager can call this function"
        );
        dumpNumberToSignatureHash[dumpNumberToConfirm] = keccak256(
            abi.encodePacked(rs, ss, vs)
        );
        dataLayr.confirm(dumpNumberToConfirm, ferkleRoot, rs, ss, vs);
    }

    //an operator can commit that they deserve `amount` payment for their service since their last payment to toDumpNumber
    // TODO: collateral
    function commitPayment(uint48 toDumpNumber, uint120 amount) external {
        require(
            queryManager.getRegistrantType(msg.sender) != 0,
            "Only registrants can call this function"
        );
        require(toDumpNumber <= dumpNumber, "Cannot claim future payments");

        if (operatorToPayment[msg.sender].fromDumpNumber == 0) {
            //this is the first payment commited, it must be claiming payment from when the operator registered
            uint48 fromDumpNumber = IDataLayrVoteWeigher(
                address(queryManager.voteWeighter())
            ).getOperatorFromDumpNumber(msg.sender);
            require(fromDumpNumber < toDumpNumber, "invalid payment range");
            operatorToPayment[msg.sender] = Payment(
                fromDumpNumber,
                toDumpNumber,
                uint32(block.timestamp),
                amount,
                0
            );
            return;
        }
        require(
            operatorToPayment[msg.sender].status == 1,
            "Require last payment is redeemed"
        );
        //you have to redeem starting from the last time redeemed up to
        uint48 fromDumpNumber = operatorToPayment[msg.sender].toDumpNumber;
        require(fromDumpNumber < toDumpNumber, "invalid payment range");
        operatorToPayment[msg.sender] = Payment(
            fromDumpNumber,
            toDumpNumber,
            uint32(block.timestamp),
            amount,
            0
        );
    }

    function redeemPayment() external { 
        require(block.timestamp >
                operatorToPayment[msg.sender].commitTime +
                    paymentFraudProofInterval &&
                operatorToPayment[msg.sender].status == 0 &&
                operatorToPaymentChallenge[msg.sender] == address(0)),
            "Still eligible for fraud proofs"
        );
        paymentToken.transfer(msg.sender, operatorToPayment[msg.sender].amount);
        operatorToPayment[msg.sender].status = 1;
    }

    //a fraud prover can challenge a payment to initiate an interactive arbitrum type proof
    //TODO: How much collateral
    function challengePaymentInit(
        address operator,
        uint120 amount1,
        uint120 amount2
    ) external {
        require(block.timestamp <
                operatorToPayment[operator].commitTime +
                    paymentFraudProofInterval &&
                operatorToPayment[operator].status == 0 &&
                operatorToPaymentChallenge[operator] == address(0)),
            "Fraud proof interval has passed"
        );
        operatorToPayment[operator].status = 2;
        operatorToPayment[operator].commitTime = uint32(block.timestamp);
        // deploy new challenge contract
        operatorToPaymentChallenge[operator] = new DataLayrPaymentChallenge(
            operator,
            msg.sender,
            operatorToPayment[operator].fromDumpNumber,
            operatorToPayment[operator].toDumpNumber,
            amount1,
            amount2
        );
    }

    function resolvePaymentChallenge(
        address operator,
        bool winner
    ) external {
        require(msg.sender == operatorToPaymentChallenge[operator], "Only the payment challenge contract can call");
        if(winner) {
            // operator was correct, allow for another challenge
            operatorToPayment[operator].status = 0;
            operatorToPayment[operator].commitTime = block.timestamp;
        } else {
            // challeger was correct, reset payment
            operatorToPayment[operator].status = 1;
        }
    }

    function getDumpNumberFee(uint48 _dumpNumber)
        public
        view
        returns (uint256)
    {
        return dumpNumberToFee[_dumpNumber];
    }

    function getDumpNumberSignatureHash(uint48 _dumpNumber)
        public
        view
        returns (bytes32)
    {
        return dumpNumberToSignatureHash[_dumpNumber];
    }

    function payFee(address payer) external payable {
        revert();
    }

    function onResponse(
        bytes32 queryHash,
        address operator,
        bytes32 reponseHash,
        uint256 senderWeight
    ) external {}
}
