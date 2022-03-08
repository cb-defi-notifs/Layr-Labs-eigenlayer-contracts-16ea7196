// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IERC20.sol";
import "../../interfaces/MiddlewareInterfaces.sol";
import "../../interfaces/CoreInterfaces.sol";
import "../../interfaces/DataLayrInterfaces.sol";
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
    // mapping(address =>)
    mapping(uint64 => bytes32) public dumpNumberToSignatureHash;
    mapping(uint64 => uint256) public dumpNumberToFee;
    mapping(address => Payment) public operatorToPayment;
    mapping(address => PaymentChallenge) public operatorToPaymentChallenge;

    // Payment
    struct Payment {
        uint48 fromDumpNumber; // dumpNumber payment being claimed from
        uint48 toDumpNumber; // dumpNumber payment being claimed to exclusive
        // payment for range [fromDumpNumber, toDumpNumber)
        uint32 commitTime; // when commited, used for fraud proof period
        uint120 amount; // max 1.3e36, keep in mind for token decimals
        uint8 status; // 0: commited, 1: redeemed,
        // 2: initially challenged (operator turn), 3: challenged first half (operator turn),
        // 4: challenged second half (operator turn), 5: challenged 1 dump first half (operator turn),
        // 6: challenged 1 dump second half (operator turn), 7: challenge (challenger turn)
    }

    struct PaymentChallenge {
        address challenger;
        uint48 fromDumpNumber;
        uint48 toDumpNumber;
        uint120 amount1;
        uint120 amount2;
    }

    event PaymentChallengeSuccess(
        address challenger,
        address adversary,
        uint32 paymentTime
    );

    event CommitPayment(address claimer, uint32 time, uint128 amount);

    event RedeemPayment(address claimer);

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
            queryManager.getIsRegistrantActive(msg.sender),
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

    //a fraud prover can challenge a payment to initiate an interactive arbitrum type proof
    //TODO: How much collateral
    function challengePaymentInit(address operator) external {
        //either challenged for first time in fraud proof interval or
        //for a future time after interval but before expiry of future challenge period
        require(
            (block.timestamp <
                operatorToPayment[operator].commitTime +
                    paymentFraudProofInterval &&
                operatorToPaymentChallenge[operator].challenger == address(0) &&
                operatorToPayment[operator].status == 0) ||
                (block.timestamp >
                    operatorToPayment[operator].commitTime +
                        paymentFraudProofInterval &&
                    block.timestamp <
                    operatorToPayment[operator].commitTime +
                        2 *
                        paymentFraudProofInterval &&
                    operatorToPaymentChallenge[operator].challenger !=
                    address(0) &&
                    operatorToPayment[operator].status == 7),
            "Fraud proof interval has passed"
        );
        operatorToPayment[operator].status = 2;
        operatorToPayment[operator].commitTime = uint32(block.timestamp);
        operatorToPaymentChallenge[operator].challenger = msg.sender;
    }

    //an operator can respond to challenges and breakdown the amount
    function respondToPaymentChallenge(uint120 amount1, uint120 amount2)
        external
    {
        require(
            block.timestamp <
                operatorToPayment[msg.sender].commitTime +
                    paymentFraudProofInterval,
            "Fraud proof interval has passed"
        );
        uint8 status = operatorToPayment[msg.sender].status;
        //if challenge is initing, break the entire payment into two halves
        if (status == 2) {
            require(
                amount1 + amount2 == operatorToPayment[msg.sender].amount,
                "Invalid amount breakdown"
            );
        } else if (status == 3) {
            //if first half is challenged, break the first half of the payment into two halves
            require(
                amount1 + amount2 ==
                    operatorToPaymentChallenge[msg.sender].amount1,
                "Invalid amount breakdown"
            );
        } else if (status == 4) {
            //if second half is challenged, break the second half of the payment into two halves
            require(
                amount1 + amount2 ==
                    operatorToPaymentChallenge[msg.sender].amount2,
                "Invalid amount breakdown"
            );
        } else {
            revert("Not in operator challenge phase");
        }
        operatorToPayment[msg.sender].status = 7;
        operatorToPayment[msg.sender].commitTime = uint32(block.timestamp);
        operatorToPaymentChallenge[msg.sender].amount1 = amount1;
        operatorToPaymentChallenge[msg.sender].amount2 = amount2;
    }

    //an operator can respond to challenges and breakdown the amount
    function respondToPaymentChallengeFinal(
        bytes32 ferkleRoot,
        uint120 amount,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        uint8[] calldata vs
    ) external {
        require(
            block.timestamp <
                operatorToPayment[msg.sender].commitTime +
                    paymentFraudProofInterval,
            "Fraud proof interval has passed"
        );
        uint48 challengedDumpNumber = operatorToPaymentChallenge[msg.sender]
            .fromDumpNumber;
        uint8 status = operatorToPayment[msg.sender].status;
        //check sigs
        dumpNumberToSignatureHash[challengedDumpNumber] = keccak256(
            abi.encodePacked(rs, ss, vs)
        );
        //calculate the true amount deserved
        uint120 trueAmount;
        for (uint256 i = 0; i < rs.length; i++) {
            address addr = ecrecover(ferkleRoot, 27 + vs[i], rs[i], ss[i]);
            if (addr == msg.sender) {
                trueAmount = uint120(
                    dumpNumberToFee[challengedDumpNumber] / (rs.length)
                );
                break;
            }
        }
        if (status == 5) {
            require(
                trueAmount == operatorToPaymentChallenge[msg.sender].amount1,
                "Invalid amount breakdown"
            );
            //TODO: Resolve here
            operatorToPayment[msg.sender].status = 0;
        } else if (status == 6) {
            //if first half is challenged, break the first half of the payment into two halves
            require(
                trueAmount == operatorToPaymentChallenge[msg.sender].amount2,
                "Invalid amount breakdown"
            );
            //TODO: Resolve here
            operatorToPayment[msg.sender].status = 0;
        } else {
            revert("Not in operator 1 dump challenge phase");
        }
        operatorToPayment[msg.sender].status = 1;
    }

    //challenger challenges a particular half of the payment
    function challengePaymentHalf(address operator, bool half) external {
        require(
            operatorToPaymentChallenge[operator].challenger == msg.sender,
            "Only challenger can continue challenge"
        );
        require(
            operatorToPayment[operator].status == 4,
            "Payment is not in challenger phase"
        );
        require(
            block.timestamp <
                operatorToPayment[operator].commitTime +
                    paymentFraudProofInterval,
            "Fraud proof interval has passed"
        );
        uint48 fromDumpNumber;
        uint48 toDumpNumber;
        if (fromDumpNumber == 0) {
            fromDumpNumber = operatorToPayment[operator].fromDumpNumber;
            toDumpNumber = operatorToPayment[operator].toDumpNumber;
        } else {
            fromDumpNumber = operatorToPaymentChallenge[operator]
                .fromDumpNumber;
            toDumpNumber = operatorToPaymentChallenge[operator].toDumpNumber;
        }
        uint48 diff = toDumpNumber - fromDumpNumber;
        //change interval to the one challenger cares about
        // if the difference between the current start and end is even, the new interval has an endpoint halfway inbetween
        // if the difference is odd = 2n + 1, the new interval has a "from" endpoint at (start + n = end - (n + 1)) if the second half is challenged,
        //                                                      or a "to" endpoint at (end - (2n + 2)/2 = end - (n + 1) = start + n) if the first half is challenged
        if (half) {
            operatorToPaymentChallenge[operator].fromDumpNumber =
                fromDumpNumber +
                diff /
                2;
            operatorToPaymentChallenge[operator].toDumpNumber = toDumpNumber;
            if (diff == 1) {
                operatorToPayment[operator].status = 5;
            } else {
                operatorToPayment[operator].status = 4;
            }
        } else {
            if (diff % 2 == 1) {
                diff += 1;
            }
            diff /= 2;
            operatorToPaymentChallenge[operator].toDumpNumber =
                toDumpNumber -
                diff;
            operatorToPaymentChallenge[operator]
                .fromDumpNumber = fromDumpNumber;
            if (diff == 1) {
                operatorToPayment[operator].status = 6;
            } else {
                operatorToPayment[operator].status = 3;
            }
        }
        operatorToPayment[operator].commitTime = uint32(block.timestamp);
    }

    function resolveChallenge(address operator) public {
        require(
            block.timestamp >
                operatorToPayment[operator].commitTime +
                    paymentFraudProofInterval &&
                block.timestamp <
                operatorToPayment[operator].commitTime +
                    2 *
                    paymentFraudProofInterval,
            "Fraud proof interval has passed"
        );
        uint8 status = operatorToPayment[operator].status;
        require(
            status == 2 ||
                status == 3 ||
                status == 4 ||
                status == 5 ||
                status == 6,
            "Not operators turn"
        );
        operatorToPayment[msg.sender].status = 1;
        //TODO: Resolve here
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
