// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IERC20.sol";
import "../../interfaces/MiddlewareInterfaces.sol";
import "../../interfaces/CoreInterfaces.sol";
import "../../interfaces/IDataLayr.sol";
import "../QueryManager.sol";

contract DataLayrServiceManager is IFeeManager {
    IVoteWeighter public voteWeighter;
    IEigenLayrDelegation public eigenLayrDelegation;
    uint256 public feePerBytePerTime;
    uint256 public paymentFraudProofInterval = 7 days;
    IDataLayr public dataLayr;
    IERC20 public paymentToken;
    IQueryManager public queryManager;
    uint256 public dumpNumber;
    // mapping(address =>)
    mapping(uint256 => bytes32) public dumpNumberToSignatureHash;
    mapping(uint256 => uint256) public dumpNumberToFee;

    // Payment
    struct Payment {
        uint128 amount;
        uint32 from;
        uint32 to;
        uint32 commitTime;
        uint8 redeemed; // Use as bool
    }

    mapping(address => Payment) public payments;

    event PaymentChallengeSuccess(
        address challenger,
        address adversary,
        uint32 paymentTime
    );

    event CommitPayment(address claimer, uint32 time, uint128 amount);

    event RedeemPayment(address claimer);

    constructor(
        IEigenLayrDelegation _eigenLayrDelegation,
        IVoteWeighter _voteWeighter
    ) {
        eigenLayrDelegation = _eigenLayrDelegation;
        voteWeighter = _voteWeighter;
    }

    function setQueryManager(IQueryManager _queryManager) public {
        require(
            address(queryManager) == address(0),
            "Query Manager already set"
        );
        queryManager = _queryManager;
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
        require(
            storePeriodLength < 604800, "store for less than 7 days"
        );
        // fees as a function of bytes of data and time to store it
        uint256 fee = totalBytes * storePeriodLength * feePerBytePerTime;
        dumpNumber++;
        dumpNumberToFee[dumpNumber] = fee;
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
    function commitSignatures(
        uint256 dumpNumberToCommit,
        bytes32 ferkleRoot,
        bytes32[] calldata rs, 
        bytes32[] calldata ss, 
        uint8[] calldata vs
    ) external payable {
        require(
            msg.sender == address(queryManager),
            "Only the query manager can call this function"
        );
        dumpNumberToSignatureHash[dumpNumberToCommit] = keccak256(abi.encodePacked(rs, ss, vs));
        dataLayr.commit(
            dumpNumberToCommit,
            ferkleRoot,
            rs, ss, vs
        );
    }   

    function commitPayment(
        uint256 dumpNumberToCommit,
        bytes32 ferkleRoot,
        bytes32[] calldata rs, 
        bytes32[] calldata ss, 
        uint8[] calldata vs
    ) external payable {
        require(
            msg.sender == address(queryManager),
            "Only the query manager can call this function"
        );
        dumpNumberToSignatureHash[dumpNumberToCommit] = keccak256(abi.encodePacked(rs, ss, vs));
        dataLayr.commit(
            dumpNumberToCommit,
            ferkleRoot,
            rs, ss, vs
        );
    }  

    function payFee(address payer) external payable {}

    function onResponse(
        bytes32 queryHash,
        address operator,
        bytes32 reponseHash,
        uint256 senderWeight
    ) external {}
}
