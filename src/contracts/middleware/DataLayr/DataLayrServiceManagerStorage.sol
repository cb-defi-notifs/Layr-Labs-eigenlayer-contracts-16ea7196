// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IRepository.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IDataLayr.sol";
import "../../interfaces/IDataLayrRegistry.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/IServiceManager.sol";
import "./DataLayrPaymentChallengeFactory.sol";

abstract contract DataLayrServiceManagerStorage is IDataLayrServiceManager, IServiceManager {
    
    // DATA STRUCTURE

    /**
     @notice used for storing information on the most recent payment made to the DataLayr operator
     */
    struct Payment {
        // dataStoreId starting from which payment is being claimed 
        uint32 fromDataStoreId; 

        // dataStoreId until which payment is being claimed (exclusive) 
        uint32 toDataStoreId; 

        // recording when committment for payment made; used for fraud proof period
        uint32 commitTime; 

        // payment for range [fromDataStoreId, toDataStoreId)
        /// @dev max 1.3e36, keep in mind for token decimals
        uint120 amount; 


        uint8 status; // 0: commited, 1: redeemed
        uint256 collateral; //account for if collateral changed
    }

    struct LowDegreeChallenge {
        uint32 commitTime; 
        address challenge;
        uint256 collateral; //account for if collateral changed
    }

    struct PaymentChallenge {
        address challenger;
        uint32 fromDataStoreId;
        uint32 toDataStoreId;
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

        // address of challenge contract if there is one - updated in initInterpolatingPolynomialFraudProof function
        // in DataLayrServiceManager.sol 
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

        // Proof [Pi(s).x, Pi(s).y] with respect to C(s) - I_k(s)
        // updated in respondToDisclosureInit function in DataLayrServiceManager.sol 
        uint256 x; //commitment coordinates
        uint256 y;


        bytes32 polyHash;

        uint32 chunkNumber;

        uint256 collateral; //account for if collateral changed
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

    struct DataStoresForDuration{
        uint32 one_duration;
        uint32 two_duration;
        uint32 three_duration;
        uint32 four_duration;
        uint32 five_duration;
        uint32 six_duration;
        uint32 dataStoreId;
        uint32 latestTime;
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
    //uint32 public dataStoreId = 1;
    uint32 public latestTime;

    //total debts owed to dlns
    mapping(address => uint256) public depositsOf;

    /// @notice indicates the window within which DataLayr operator must respond to the SignatoryRecordMinusDataStoreId disclosure challenge 
    uint256 public constant disclosureFraudProofInterval = 7 days;


    uint256 disclosurePaymentPerByte;

    uint256 public constant lowDegreeFraudProofInterval = 7 days;


    /**
     @notice map of forced disclosure challenge that has been opened against a DataLayr operator
             for a particular DataStoreId.   
     */
    mapping(bytes32 => mapping(address => DisclosureChallenge)) public disclosureForOperator;

    uint48 public numPowersOfTau; // num of leaves in the root tree
    uint48 public log2NumPowersOfTau; // num of leaves in the root tree

    //TODO: store these upon construction
    // Commitment(0), Commitment(x - w), Commitment((x-w)(x-w^2)), ...
    /**
     @notice For a given l, zeroPolynomialCommitmentMerkleRoots[l] represents the root of merkle tree 
     that is given by:

                                    zeroPolynomialCommitmentMerkleRoots[l]
                                                        :    
                                                        :    
                         ____________ ....                             .... ____________              
                        |                                                               |
                        |                                                               |    
              _____h(h_1||h_2)______                                        ____h(h_{k-1}||h_{k}__________  
             |                      |                                      |                              |   
             |                      |                                      |                              |
            h_1                    h_2                                 h_{k-1}                         h_{k} 
             |                      |                                      |                              |  
             |                      |                                      |                              |  
     hash(x^l - w^l)       hash(x^l - (w^2)^l)                   hash(x^l - (w^{k-1})^l)        hash(x^l - (w^k)^l) 
     
     This tree is computed off-chain and only the Merkle roots are stored on-chain.
     */
    // CRITIC: does that mean there are only 32 possible 32 possible merkle trees? 
    bytes32[32] public zeroPolynomialCommitmentMerkleRoots;

    /**
     * @notice mapping between the dataStoreId for a particular assertion of data into
     *         DataLayr and a compressed information on the signatures of the DataLayr 
     *         nodes who signed up to be the part of the quorum.  
     */
    mapping(uint32 => bytes32) public dataStoreIdToSignatureHash;

    /**
     * @notice mapping between the total service fee that would be paid out in the 
     *         corresponding assertion of data into DataLayr 
     */
    //removed to batch with DataStoreMetadata
    //mapping(uint32 => uint256) public dataStoreIdToFee;

    mapping(bytes32 => mapping(address => LowDegreeChallenge)) public lowDegreeChallenges;

    /**
     * @notice mapping between the operator and its current committed or payment
     *         or the last redeemed payment 
     */
    mapping(address => Payment) public operatorToPayment;

    /**     
      @notice the latest expiry period (in UTC timestamp) out of all the active Data blobs stored in DataLayr;
              updated at every call to initDataStore in DataLayrServiceManager.sol  

              This would be used for recording the time until which a DataLayr operator is obligated
              to serve while committing deregistration.
     */
    
    mapping(address => address) public operatorToPaymentChallenge;

    uint256 constant public DURATION_SCALE = 1 hours;
    // NOTE: these values are measured in *DURATION_SCALE*
    uint8 constant public MIN_DATASTORE_DURATION = 1;
    uint8 constant public MAX_DATASTORE_DURATION = 14;

    //mapping from duration to timestamp to all of the ids of datastores that were initialized during that timestamp
    mapping(uint8 => mapping(uint256 => bytes32)) public dataStoreIdsForDuration;
    //total number of datastores that have been stored for a certain duration
    mapping(uint8 => uint32) public totalDataStoresForDuration;

    //a deposit root is posted every depositRootInterval dumps
    uint16 public constant depositRootInterval = 1008; //this is once a week if dumps every 10 mins
    mapping(uint256 => bytes32) public depositRoots; // blockNumber => depositRoot
 
    constructor(IERC20 _paymentToken, IERC20 _collateralToken) {
        paymentToken = _paymentToken;
        collateralToken = _collateralToken;
    }
}
