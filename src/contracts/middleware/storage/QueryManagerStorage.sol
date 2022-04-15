// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IRegistrationManager.sol";
import "../../interfaces/IInvestmentStrategy.sol";
import "../../interfaces/IInvestmentManager.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/IQueryManager.sol";
import "../../utils/Timelock_Managed.sol";

/**
 * @notice This contract specifies all the state variables that are being used 
 *         within QueryManager contract.
 */
abstract contract QueryManagerStorage is Timelock_Managed, IQueryManager {

    /**
     * @notice This struct is used for containing the details of a query that is created 
     *         by the middleware for validation in EigenLayr.
     */
    struct Query {
        // hash(reponse) with the greatest cumulative weight
        bytes32 leadingResponse;
        // hash(finalized response). initialized as 0x0, updated if/when query is finalized
        bytes32 outcome;
        // sum of all cumulative weights
        uint256 totalCumulativeWeight;
        // hash(response) => cumulative weight
        mapping(bytes32 => uint256) cumulativeWeights;
        // operator => hash(response)
        mapping(address => bytes32) responses;
        // operator => weight
        mapping(address => uint256) operatorWeights;
    }

    //called when responses are provided by operators
    IVoteWeigher public voteWeigher;
    IEigenLayrDelegation public delegation;
    IInvestmentManager public investmentManager;
    //called when new queries are created. handles payments for queries.
    IFeeManager public feeManager;

    /**
     * @notice For each investment strategy "strat" that is part of any delegator's investment strategy
     *         portfolio of any operator registered with the middleware, shares[strat] is the 
     *         cumulative sum of shares of all such delegators for that startegy "strat" across all
     *         all the operators of that middleware. 
     */
    mapping(IInvestmentStrategy => uint256) public shares;


    /**
     * @notice It is the array of all investment strategies whose corresponding entry in above 
     *         "shares" mapping is non-zero.
     */
    IInvestmentStrategy[] public strats;

    /**
     * @notice TBA.
     */
    mapping(address => mapping(IInvestmentStrategy => uint256))
        public operatorShares;


    /**
     * @notice For each operator "op", operatorStrats[op] is the list of all investment strategies
     *         that any delegator to that operator "op" is employing.    
     */    
    mapping(address => IInvestmentStrategy[]) public operatorStrats;

    /**
     * @notice For each operator "op", eigenDeposited[op] is the cumulative amount of Eigen that
     *         is being employed by the operator for providing service to the middleware via EigenLayr.  
     */
    mapping(address => uint256) public eigenDeposited;

    // mapping from each operator's address to its Stake for the middleware
    mapping(address => Stake) public operatorStakes;

    // variable for storing total ETH and Eigen staked into securing the middleware
    Stake public totalStake;

    uint256 public consensusLayerEthToEth;
    mapping(address => uint256) public consensusLayerEth;
    uint256 public totalConsensusLayerEth;
    
    // fixed duration of all new queries
    uint256 public queryDuration;
    
    
    // number of registrants of this service
    uint256 public numRegistrants;

    /**
     * @notice For any operator "op", operatorType[op] = 0 would imply an unregistered operator 
     *         with the query manager for the associated middleware. For registered operators,
     *         operatorType[op] would be some non-zero integer depending on the type of assets
     *         that has been staked by the operator "op" for providing service to the middleware. 
     */
    mapping(address => uint8) public operatorType;


    IRegistrationManager public registrationManager;

    /**
     * @notice Each query is mapped to its hash, which is used as its identifier.
     */
    mapping(bytes32 => Query) public queries;


    /**
     * @notice Hash of each query is mapped to the corresponding creation time of the query.
     */
    mapping(bytes32 => uint256) public queriesCreated;

    /**
     * @notice Array of all active queries.
     */
    bytes32[] public activeQueries;


    /// @notice 32 bits for all 7 operatorTypes (1 through 7), 32 bits for the total number of operators
    /**
     * @dev It is an integrated storage variable that stores the number of operators for each 
     *      operator type. The structure of this storage variable is based on following assumptions:
     *         - there can be, at max, 7 operator types
     *         - there can be at max 2**32 operators of each type
     *         - there can be at max 2**32 total operators
     *         
     *      We use 8 bits to represent each of the operatorType, 32 bits to represent number of
     *      operators for each operatorType, 32 bits to represent total operators. Let bit 
     *      representation of i^th operatorType be <o_i>, bit representation of number of operators 
     *      of i^th operatorType be <n_i> and bit representation of total number of operators
     *      be <n>. Considering these specifics, we have the following structure:
     *
     *                ++++ | ###...#|     ......     |  ++++  |###...# | ++++ | ###...# | $$$....$
     *               <o_7> |  <n_7> | (omitted bits) | <o_2>  | <n_2>  | <o_1>|  <n_1>  |    <n> 
     *      where each +, #, $ represents a bit. 
     */
    uint256 public operatorCounts;
}