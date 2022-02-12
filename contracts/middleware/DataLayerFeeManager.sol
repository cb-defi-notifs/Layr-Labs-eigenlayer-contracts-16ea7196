// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/MiddlewareInterfaces.sol";
import "../interfaces/CoreInterfaces.sol";
import "../interfaces/IDataLayr.sol";
import "./QueryManager.sol";

//TODO: 
contract DataLayrFeeManager is IFeeManager {
    IInvestmentManager public investmentManager;
    IVoteWeighter public voteWeighter;
    uint256 public feePerBytePerTime;
    uint256 public paymentFraudProofInterval = 7 days;
    IDataLayr public dataLayr;
    IQueryManager public queryManager;

    // Payment
    struct Payment {
        uint128 amount;
        uint32 from;
        uint32 to;
        uint32 commitTime;
        uint8 redeemed; // Use as bool
    }

    mapping(address => Payment) public payments;

     event PaymentChallengeSuccess (
        address challenger,
        address adversary,
        uint32 paymentTime
    );

    event CommitPayment (
        address claimer,
        uint32 time,
        uint128 amount
    );

    event RedeemPayment (
        address claimer
    );

    constructor(IInvestmentManager _investmentManager, IVoteWeighter _voteWeighter){
        investmentManager = _investmentManager;
        voteWeighter = _voteWeighter;
    }

    function setQueryManager(IQueryManager _queryManager) public {
        require(address(queryManager) == address(0), "Query Manager already set");
        queryManager = _queryManager;
    }

    function payFeeForDataStore(bytes32 ferkleRoot, uint32 totalBytes, uint32 storePeriodLength, address submitter, uint24 quorum) external payable {
        uint256 fee = totalBytes * storePeriodLength * feePerBytePerTime;
        require(msg.value == fee, "Incorrect Fee paid");
        dataLayr.initDataStore(ferkleRoot, totalBytes, storePeriodLength, submitter, quorum);
    }

    function commitPayment(uint32 time, uint128 amount) public {
        require(payments[msg.sender].redeemed == 1, "Last payment hasn't been settled or redeemed" );
        require(block.timestamp >= time, "Cannot redeem future payouts");
        require(time > payments[msg.sender].to, "Cannot be paid from before last payment time" );

        payments[msg.sender] = Payment(
            amount,                                 // amount
            payments[msg.sender].to, // from
            time,                                   // to
            uint32(block.timestamp),                // commitTime
            0                                       // redeemed
        );
        emit CommitPayment(msg.sender, time, amount);
    }

    function verifySignature(bytes32[] calldata rs, bytes32[] calldata ss, uint8[] calldata vs, bytes32 commitHash) view internal{
        for(uint i=0; i<rs.length; i++){
            address addr = ecrecover(commitHash, 27 + vs[i], rs[i], ss[i]);
            require(queryManager.getIsRegistrantActive(addr), "addr not exist");
        }
    }

    function challengePayment(address adversary, uint32 from, uint32 to, bytes32[] calldata rs, bytes32[] calldata ss, uint8[] calldata vs) external {
        require(rs.length >= ceil(queryManager.numRegistrants(), 2), "Insufficient sig");
        require(payments[adversary].redeemed == 0, "Data store doesn't have commitHash");
        
        verifySignature(rs, ss, vs, keccak256(abi.encodePacked(adversary,from,to)));

        emit PaymentChallengeSuccess(msg.sender, adversary, to);
    }

    function redeemPayment() public payable {
        require(
            payments[msg.sender].redeemed == 0,
            "Payment must not be redeemed yet"
        );
        require(
            payments[msg.sender].commitTime +
                paymentFraudProofInterval <
                block.timestamp,
            "Cannot redeem future payouts"
        );
        payments[msg.sender].redeemed = 1;
        payable(msg.sender).transfer(payments[msg.sender].amount);

        emit RedeemPayment(msg.sender);
    }

    function ceil(uint a, uint b) pure internal returns (uint) {
        require(b>0);
        return (a + b - 1) / b;
    }

    function payFee(address payer) external payable {}

	function onResponse(bytes32 queryHash, address operator, bytes32 reponseHash, uint256 senderWeight) external {}
}