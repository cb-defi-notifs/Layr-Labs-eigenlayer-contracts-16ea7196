// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IDataLayr.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/IServiceManager.sol";
import "../../interfaces/IInvestmentManager.sol";
import "./DataLayrPaymentManager.sol";
import "./DataLayrLowDegreeChallenge.sol";
import "./DataLayrDisclosureChallenge.sol";
import "./DataLayrBombVerifier.sol";
import "../EphemeralKeyRegistry.sol";
import "../../permissions/RepositoryAccess.sol";

abstract contract DataLayrServiceManagerStorage is IDataLayrServiceManager, RepositoryAccess {
    // collateral token used for placing collateral on challenges & payment commits
    IERC20 public immutable collateralToken;

    /**
     * @notice The EigenLayr delegation contract for this DataLayr which is primarily used by
     *      delegators to delegate their stake to operators who would serve as DataLayr
     *      nodes and so on.
     */
    /**
      @dev For more details, see EigenLayrDelegation.sol. 
     */
    IEigenLayrDelegation public immutable eigenLayrDelegation;

    IInvestmentManager public immutable investmentManager;

    /**
     * @notice service fee that will be paid out by the disperser to the DataLayr nodes
     *         for storing per byte for per unit time. 
     */
    uint256 public feePerBytePerTime;

    /// @notice counter for number of assertions of data that has happened on this DataLayr
    //uint32 public dataStoreId = 1;
    
    uint256 public disclosurePaymentPerByte;

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
      @notice the latest expiry period (in UTC timestamp) out of all the active Data blobs stored in DataLayr;
              updated at every call to initDataStore in DataLayrServiceManager.sol  

              This would be used for recording the time until which a DataLayr operator is obligated
              to serve while committing deregistration.
     */
    
    uint256 constant public DURATION_SCALE = 1 hours;
    uint256 constant public NUM_DS_PER_BLOCK_PER_DURATION = 10;
    // NOTE: these values are measured in *DURATION_SCALE*
    uint8 constant public MIN_DATASTORE_DURATION = 1;
    uint8 constant public MAX_DATASTORE_DURATION = 14;

    //mapping from duration to timestamp to all of the ids of datastores that were initialized during that timestamp.
    //the third nested mapping just keeps track of a fixed number of datastores of a certain duration that can be
    //in that block
    mapping(uint8 => mapping(uint256 =>  bytes32[NUM_DS_PER_BLOCK_PER_DURATION])) public dataStoreHashesForDurationAtTimestamp;
    //total number of datastores that have been stored for a certain duration
    mapping(uint8 => uint32) public totalDataStoresForDuration;

    //a deposit root is posted every depositRootInterval dumps
    uint16 public constant depositRootInterval = 1008; //this is once a week if dumps every 10 mins
    mapping(uint256 => bytes32) public depositRoots; // blockNumber => depositRoot
 
    DataLayrLowDegreeChallenge public dataLayrLowDegreeChallenge;

    DataLayrDisclosureChallenge public dataLayrDisclosureChallenge;

    DataLayrBombVerifier public dataLayrBombVerifier;

    EphemeralKeyRegistry public ephemeralKeyRegistry;



    /**
     * @notice contract used for handling payment challenges
     */
    IDataLayrPaymentManager public dataLayrPaymentManager;

    constructor(IInvestmentManager _investmentManager, IEigenLayrDelegation _eigenLayrDelegation, IERC20 _collateralToken) 
    {
        investmentManager = _investmentManager;
        eigenLayrDelegation = _eigenLayrDelegation;
        collateralToken = _collateralToken;
    }
}
