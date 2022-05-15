// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IRepository.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IDataLayr.sol";
import "../../interfaces/IDataLayrRegistry.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "./DataLayrPaymentChallengeFactory.sol";

abstract contract DataLayrServiceManagerStorage is IDataLayrServiceManager, IServiceManager {
    
    // DATA STRUCTURE

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

    struct PaymentChallenge {
        address challenger;
        uint32 fromDumpNumber;
        uint32 toDumpNumber;
        uint120 amount1;
        uint120 amount2;
    }

    /**
     @notice used for storing information on the forced disclosure challenge    
     */
    struct DisclosureChallenge {
        // instant when forced disclosure challenge was made
        uint32 commitTime;

        // challenger's address
        address challenger; 

        // address of challenge contract if there is one
        address challenge;

        // 
        uint48 degree;

        /** 
            Used for indicating the status of the forced disclosure challenge. The status are:
                - 1: challenged, 
                - 2: responded (in fraud proof period), 
                - 3: challenged commitment, 
                - 4: operator incorrect
         */
        uint8 status; 


        uint256 x; //commitment coordinates
        uint256 y;
        bytes32 polyHash;
    }

    struct MultiReveal {
        uint256 i_x;
        uint256 i_y;
        uint256 pi_x;
        uint256 pi_y;
    }

    struct Commitment {
        uint256 x;
        uint256 y;
    }

    /**
     * @notice the ERC20 token that will be used by the disperser to pay the service fees to
     *         DataLayr nodes.
     */
    IERC20 public immutable paymentToken;

    IERC20 public immutable collateralToken;

    IDataLayr public dataLayr;
    IRepository public repository;

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


    /**
     @notice this is the payment that has to be made as a collateral for fraudproof 
             during payment challenges
     */
    uint256 public paymentFraudProofCollateral = 1 wei;




    /// @notice counter for number of assertions of data that has happened on this DataLayr
    uint32 public dumpNumber = 1;
    
    /// @notice indicates the window within which DataLayr operator must respond to the forced disclosure challenge 
    uint256 public constant disclosureFraudProofInterval = 7 days;


    uint256 disclosurePaymentPerByte;



    /**
     @notice map of forced disclosure challenge that has been opened against a DataLayr operator
             for a particular dump number.   
     */
    mapping(bytes32 => mapping(address => DisclosureChallenge)) disclosureForOperator;


    bytes32 public powersOfTauMerkleRoot;
    uint48 public numPowersOfTau; // num of leaves in the root tree
    uint48 public log2NumPowersOfTau; // num of leaves in the root tree

    //TODO: store these upon construction
    // Commitment(0), Commitment(x - w), Commitment((x-w)(x-w^2)), ...
    bytes32[32] public zeroPolynomialCommitmentMerkleRoots;

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
 
    constructor(IERC20 _paymentToken, IERC20 _collateralToken) {
        paymentToken = _paymentToken;
        collateralToken = _collateralToken;
    }
}
