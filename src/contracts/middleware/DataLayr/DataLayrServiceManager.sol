// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IQueryManager.sol";
import "../../interfaces/DataLayrInterfaces.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/ProofOfStakingInterfaces.sol";
import "./storage/DataLayrServiceManagerStorage.sol";
import "./DataLayrPaymentChallenge.sol";
import "./DataLayrSignatureChecker.sol";
import "../QueryManager.sol";

contract DataLayrServiceManager is
    DataLayrSignatureChecker,
    IProofOfStakingOracle
{

    IEigenLayrDelegation public immutable eigenLayrDelegation;
    IERC20 public immutable paymentToken;
    IERC20 public immutable collateralToken;
    constructor(
        IEigenLayrDelegation _eigenLayrDelegation,
        IERC20 _paymentToken,
        IERC20 _collateralToken
    ) {
        eigenLayrDelegation = _eigenLayrDelegation;
        paymentToken = _paymentToken;
        collateralToken = _collateralToken;
    }

    modifier onlyQMGovernance() {
        require(
            queryManager.timelock() == msg.sender,
            "Query Manager governance can only call this function"
        );
        _;
    }

    function setQueryManager(IQueryManager _queryManager) public {
        require(
            address(queryManager) == address(0),
            "Query Manager already set"
        );
        queryManager = _queryManager;
        dlRegVW = IDataLayrVoteWeigher(
            address(queryManager.voteWeighter())
        );
    }

    //pays fees for a datastore leaving tha payment in this contract and calling the datalayr contract with needed information
    function payFeeForDataStore(
        bytes32 ferkleRoot,
        uint32 totalBytes,
        uint32 storePeriodLength,
        address submitter
    ) external payable {
        require(
            msg.sender == address(queryManager),
            "Only the query manager can call this function"
        );
        require(totalBytes > 32, "Can't store less than 33 bytes");
        require(storePeriodLength > 60, "store for more than a minute");
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
            submitter
        );
    }

    //checks signatures and hands off to DL
    function confirmDump(bytes calldata data) external payable {
        require(
            msg.sender == address(queryManager),
            "Only the query manager can call this function"
        );
        (
            uint64 dumpNumberToConfirm,
            bytes32 ferkleRoot,
            SignatoryTotals memory signedTotals,
            bytes32 signatoryRecordHash
        ) = checkSignatures(data);
        //make sure they shouldn't be posting a deposit root
        require(dumpNumberToConfirm % depositRootInterval != 0, "Must post a deposit root now");
        dumpNumberToSignatureHash[dumpNumberToConfirm] = signatoryRecordHash;
        dataLayr.confirm(
            dumpNumberToConfirm,
            ferkleRoot,
            tx.origin, //@TODO: How to we get the address that called the queryManager, may not be an EOA, it wont be
            signedTotals.totalEthSigners,
            signedTotals.totalEigenSigners
        );
    }

    //checks signatures, stores POSt hash, and hands off to DL
    function confirmDumpWithPOSt(bytes32 depositRoot, bytes32 ferkleRoot, bytes calldata data) external payable {
        require(
            msg.sender == address(queryManager),
            "Only the query manager can call this function"
        );
        (
            uint64 dumpNumberToConfirm,
            bytes32 depositFerkleHash,
            SignatoryTotals memory signedTotals,
            bytes32 signatoryRecordHash
        ) = checkSignatures(data);
        //make sure they should be posting a deposit root
        require(dumpNumberToConfirm % depositRootInterval == 0, "Shouldn't post a deposit root now");
        dumpNumberToSignatureHash[dumpNumberToConfirm] = signatoryRecordHash;
        //when posting a deposit root, DLNs will sign hash(depositRoot || ferkleRoot) instead of the usual ferkleRoot, 
        //so the submitter must specify the preimage
        require(keccak256(abi.encodePacked(depositRoot, ferkleRoot)) == depositFerkleHash, "Ferkle or deposit root is incorrect");
        //store the depost root
        depositRoots[block.number] = depositRoot;
        dataLayr.confirm(
            dumpNumberToConfirm,
            ferkleRoot,
            tx.origin, //@TODO: How to we get the address that called the queryManager, may not be an EOA, it wont be
            signedTotals.totalEthSigners,
            signedTotals.totalEigenSigners
        );
    }

    //an operator can commit that they deserve `amount` payment for their service since their last payment to toDumpNumber
    // TODO: collateral
    function commitPayment(uint48 toDumpNumber, uint120 amount) external {
        require(
            queryManager.getOperatorType(msg.sender) != 0,
            "Only registrants can call this function"
        );
        require(toDumpNumber <= dumpNumber, "Cannot claim future payments");
        //put up collateral
        collateralToken.transferFrom(
            msg.sender,
            address(this),
            paymentFraudProofCollateral
        );

        uint48 fromDumpNumber;
        if (operatorToPayment[msg.sender].fromDumpNumber == 0) {
            //this is the first payment commited, it must be claiming payment from when the operator registered
            fromDumpNumber = IDataLayrVoteWeigher(
                address(queryManager.voteWeighter())
            ).getOperatorFromDumpNumber(msg.sender);
            require(fromDumpNumber < toDumpNumber, "invalid payment range");
            operatorToPayment[msg.sender] = Payment(
                fromDumpNumber,
                toDumpNumber,
                uint32(block.timestamp),
                amount,
                0,
                paymentFraudProofCollateral
            );
            return;
        }
        require(
            operatorToPayment[msg.sender].status == 1,
            "Require last payment is redeemed"
        );
        //you have to redeem starting from the last time redeemed up to
        fromDumpNumber = operatorToPayment[msg.sender].toDumpNumber;
        require(fromDumpNumber < toDumpNumber, "invalid payment range");
        operatorToPayment[msg.sender] = Payment(
            fromDumpNumber,
            toDumpNumber,
            uint32(block.timestamp),
            amount,
            0,
            paymentFraudProofCollateral
        );
    }

    function redeemPayment() external {
        require(
            block.timestamp >
                operatorToPayment[msg.sender].commitTime +
                    paymentFraudProofInterval &&
                operatorToPayment[msg.sender].status == 0,
            "Still eligible for fraud proofs"
        );
        operatorToPayment[msg.sender].status = 1;
        paymentToken.transfer(msg.sender, operatorToPayment[msg.sender].amount);
        collateralToken.transfer(
            msg.sender,
            operatorToPayment[msg.sender].collateral
        );
    }

    //a fraud prover can challenge a payment to initiate an interactive arbitrum type proof
    //TODO: How much collateral
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
        address challengeContract = address(
            new DataLayrPaymentChallenge(
                operator,
                msg.sender,
                operatorToPayment[operator].fromDumpNumber,
                operatorToPayment[operator].toDumpNumber,
                amount1,
                amount2
            )
        );
        //move collateral over
        uint256 collateral = operatorToPayment[operator].collateral;
        collateralToken.transferFrom(msg.sender, address(this), collateral);
        //update payment
        operatorToPayment[operator].status = 2;
        operatorToPayment[operator].commitTime = uint32(block.timestamp);
        operatorToPaymentChallenge[operator] = challengeContract;
    }

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
        } else {
            // challeger was correct, reset payment
            operatorToPayment[operator].status = 1;
            //give them their collateral and the operators
            collateralToken.transfer(
                operator,
                2 * operatorToPayment[operator].collateral
            );
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

    function getPaymentCollateral(address operator)
        public
        view
        returns (uint256)
    {
        return operatorToPayment[operator].collateral;
    }

    function getDepositRoot(uint256 blockNumber) public view returns(bytes32) {
        return depositRoots[blockNumber];
    }

    function payFee(address) external payable {
        revert();
    }

    function onResponse(
        bytes32 queryHash,
        address operator,
        bytes32 reponseHash,
        uint256 senderWeight
    ) external {}

    function setFeePerBytePerTime(uint256 _feePerBytePerTime)
        public
        onlyQMGovernance
    {
        feePerBytePerTime = _feePerBytePerTime;
    }

    function setPaymentFraudProofCollateral(
        uint256 _paymentFraudProofCollateral
    ) public onlyQMGovernance {
        paymentFraudProofCollateral = _paymentFraudProofCollateral;
    }

    function setDataLayr(IDataLayr _dataLayr) public onlyQMGovernance {
        dataLayr = _dataLayr;
    }

    /* function removed for now since it tries to modify an immutable variable
    function setPaymentToken(
        IERC20 _paymentToken
    ) public onlyQMGovernance {
        paymentToken = _paymentToken;
    }
*/
}
