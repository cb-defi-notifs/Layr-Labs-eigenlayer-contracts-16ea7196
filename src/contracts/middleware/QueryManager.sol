// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../governance/Timelock.sol";
import "../interfaces/IInvestmentStrategy.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IQueryManager.sol";
import "../interfaces/IRegistrationManager.sol";
import "../utils/Initializable.sol";
// import "../utils/Timelock_Managed.sol";
import "./storage/QueryManagerStorage.sol";

/**
 * @notice This is the contract for managing queries in any middleware. Each middleware has a
 *         a query manager. The main functionalities of this contract are:
 *             - Enable mechanism for an operator to register with the middleware so that it can
 *               respond to the middleware's queries,
 *             - Enable mechanism for an operator to de-register with the middleware,
 *             - Enable mechanism for updating the stake that is being deployed by an
 *               operator for validating the queries of the middleware,
 *             - Enable mechanism for creating new queries by the middleware, responding to
 *               existing queries by operators and finalize the outcome of the queries.
 */
contract QueryManager is Initializable, QueryManagerStorage {
    // EVENTS
    event Registration(address operator);
    event Deregistration(address operator);

    event QueryCreated(bytes32 indexed queryDataHash, uint256 blockTimestamp);

    event ResponseReceived(
        address indexed submitter,
        bytes32 indexed queryDataHash,
        bytes32 indexed responseHash,
        uint256 weightAssigned
    );

    event NewLeadingResponse(
        bytes32 indexed queryDataHash,
        bytes32 indexed previousLeadingResponseHash,
        bytes32 indexed newLeadingResponseHash
    );

    event QueryFinalized(
        bytes32 indexed queryDataHash,
        bytes32 indexed outcome,
        uint256 totalCumulativeWeight
    );

    function initialize(
        IVoteWeigher _voteWeigher,
        uint256 _queryDuration,
        uint256 _consensusLayerEthToEth,
        IFeeManager _feeManager,
        IRegistrationManager _registrationManager,
        uint256 _timelockDelay,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager
    ) external initializer {
        _setVoteWeigher(_voteWeigher);
        queryDuration = _queryDuration;
        consensusLayerEthToEth = _consensusLayerEthToEth;
        feeManager = _feeManager;
        registrationManager = _registrationManager;
        Timelock _timelock = new Timelock(address(this), _timelockDelay);
        _setTimelock(_timelock);
        delegation = _delegation;
        investmentManager = _investmentManager;
    }

    /**
     * @notice Used by an operator to de-register itself from providing service to the middleware.
     */
    function deregister(bytes calldata data) external {
        require(
            operatorType[msg.sender] != 0,
            "Registrant is not registered with this middleware."
        );
        require(
            registrationManager.deregisterOperator(msg.sender, data),
            "Deregistration not permitted"
        );

        // subtract the staked Eigen and ETH of the operator, that is getting deregistered,
        // from the total stake securing the middleware
        totalStake.eigenStaked -= operatorStakes[msg.sender].eigenStaked;
        totalStake.ethStaked -= operatorStakes[msg.sender].ethStaked;

        // clear the staked Eigen and ETH of the operator which is getting deregistered
        operatorStakes[msg.sender].eigenStaked = 0;
        operatorStakes[msg.sender].ethStaked = 0;

        /**
         * @dev Referring to the detailed explanation on structure of operatorCounts in
         *      QueryManagerStorage.sol, in order to subtract the number of operators
         *      of i^th type, first left shift 1 by 32*i bits and subtract it from <n_i>.
         *      Then, subtract 1 from <n> to decrement the number of total operators.
         */
        operatorCounts =
            (operatorCounts - (1 << ((32 * operatorType[msg.sender]) + 32))) -
            1;

        // the operator is recorded as being no longer active
        operatorType[msg.sender] = 0;
        emit Deregistration(msg.sender);
    }

    // call registration contract with given data
    /**
     * @notice Used by an operator to register itself for providing service to the middleware
     *         associated with this QueryManager contract. This also notifies the stakers that
     *         the account has registered itself as an operator.
     */
    /**
     * @param data is an encoding of the operatorType that the operator wants to register as
     *        with the middleware, infrastructure details that the middleware would need for
     *        coordinating with the operator to elicit its response, etc. Details may
     *        vary from middleware to middleware.
     */
    /**
     * @dev Uses the RegistrationManager contract for registering the operator.
     */
    function register(bytes calldata data) external {
        require(
            operatorType[msg.sender] == 0,
            "Registrant is already registered"
        );

        /**
         * This function calls the registerOperator function of the middleware to process the
         * data that has been provided by the operator.
         */
        (uint8 opType, uint128 eigenAmount) = registrationManager
            .registerOperator(msg.sender, data);

        // record the operator type of the operator
        operatorType[msg.sender] = opType;

        /**
         * Get the total ETH that has been deposited by the delegators of the operator.
         * This will account for ETH that has been delegated for staking in settlement layer only
         * and the ETH that has been cinverted into the specified liquidStakeToken first which is then
         * being deposited in some investment strategy.
         */
        //SHOULD BE LESS THAN 2^128, do we need to switch everything to uint128? @TODO
        uint128 ethAmount = uint128(
            delegation.getUnderlyingEthDelegated(msg.sender) +
                delegation.getConsensusLayerEthDelegated(msg.sender) /
                consensusLayerEthToEth
        );

        // only 1 SSTORE
        operatorStakes[msg.sender] = Stake(eigenAmount, ethAmount);

        /**
         * update total Eigen and ETH tha are being employed by the operator for securing
         * the queries from middleware via EigenLayr
         */
        //i think this gets batched as 1 SSTORE @TODO check
        totalStake.eigenStaked += eigenAmount;
        totalStake.ethStaked += ethAmount;

        // increment both the total number of operators and number of operators of opType
        operatorCounts = (operatorCounts + (1 << (32 * opType + 32))) + 1;
        emit Registration(msg.sender);
    }

    /**
     * @notice This function can be called by anyone to update the assets that have been
     *         deposited by the specified operator for validation of middleware.
     */
    /**
     * @return (updated ETH, updated Eigen) staked with the operator
     */
    function updateStake(address operator)
        public
        override
        returns (uint128, uint128)
    {
        // get new updated Eigen and ETH that has been delegated by the delegators of the
        // operator
        uint128 newEigen = voteWeigher.weightOfOperatorEigen(operator);
        uint128 newEth = uint128(
            delegation.getUnderlyingEthDelegated(operator) +
                delegation.getConsensusLayerEthDelegated(operator) /
                consensusLayerEthToEth
        );

        // store old stake in memory
        uint128 prevEigen = operatorStakes[operator].eigenStaked;
        uint128 prevEth = operatorStakes[operator].ethStaked;

        // store the updated stake
        operatorStakes[operator].eigenStaked = newEigen;
        operatorStakes[operator].ethStaked = newEth;

        // update the total stake
        totalStake.eigenStaked = totalStake.eigenStaked + newEigen - prevEigen;
        totalStake.ethStaked = totalStake.ethStaked + newEth - prevEth;

        //return (updated ETH, updated Eigen) staked with the operator
        return (newEth, newEigen);
    }

    /// @notice get total ETH staked for securing the middleware
    function totalEthStaked() public view returns (uint128) {
        return totalStake.ethStaked;
    }

    /// @notice get total Eigen staked for securing the middleware
    function totalEigenStaked() public view returns (uint128) {
        return totalStake.eigenStaked;
    }

    /// @notice get total ETH staked by delegators of the operator
    function ethStakedByOperator(address operator)
        public
        view
        returns (uint128)
    {
        return operatorStakes[operator].ethStaked;
    }

    /// @notice get total Eigen staked by delegators of the operator
    function eigenStakedByOperator(address operator)
        public
        view
        returns (uint128)
    {
        return operatorStakes[operator].eigenStaked;
    }

    /// @notice get both total ETH and Eigen staked by delegators of the operator
    function ethAndEigenStakedForOperator(address operator)
        public
        view
        returns (uint128, uint128)
    {
        Stake memory opStake = operatorStakes[operator];
        return (opStake.ethStaked, opStake.eigenStaked);
    }

    /// @notice returns the type for the specified operator
    function getOperatorType(address operator)
        public
        view
        override
        returns (uint8)
    {
        return operatorType[operator];
    }

    /**
     * @notice creates a new query based on the @param queryData passed.
     */
    function createNewQuery(bytes calldata queryData) external override {
        _createNewQuery(msg.sender, queryData);
    }

    function _createNewQuery(address queryCreator, bytes calldata queryData)
        internal
    {
        bytes32 queryDataHash = keccak256(queryData);

        //verify that query has not already been created
        require(queriesCreated[queryDataHash] == 0, "duplicate query");

        //mark query as created and emit an event
        queriesCreated[queryDataHash] = block.timestamp;
        emit QueryCreated(queryDataHash, block.timestamp);

        //hook to manage payment for query
        IFeeManager(feeManager).payFee(queryCreator);
    }

    /**
     * @notice Used by operators to respond to a specific query.
     */
    /**
     * @param queryHash is the identifier for the query to which the operator is responding,
     * @param response is the operator's response for the query.
     */
    function respondToQuery(bytes32 queryHash, bytes calldata response)
        external
    {
        _respondToQuery(msg.sender, queryHash, response);
    }

    function _respondToQuery(
        address respondent,
        bytes32 queryHash,
        bytes calldata response
    ) internal {
        // make sure query is open
        require(block.timestamp < _queryExpiry(queryHash), "query period over");

        // make sure sender has not already responded to it
        require(
            queries[queryHash].operatorWeights[respondent] == 0,
            "duplicate response to query"
        );

        // find respondent's weight and the hash of their response
        uint256 weightToAssign = voteWeigher.weightOfOperatorEth(respondent);
        bytes32 responseHash = keccak256(response);

        // update Query struct with respondent's weight and response
        queries[queryHash].operatorWeights[respondent] = weightToAssign;
        queries[queryHash].responses[respondent] = responseHash;
        queries[queryHash].cumulativeWeights[responseHash] += weightToAssign;
        queries[queryHash].totalCumulativeWeight += weightToAssign;

        //emit event for response
        emit ResponseReceived(
            respondent,
            queryHash,
            responseHash,
            weightToAssign
        );

        // check if leading response has changed. if so, update leadingResponse and emit an event
        bytes32 leadingResponseHash = queries[queryHash].leadingResponse;
        if (
            responseHash != leadingResponseHash &&
            queries[queryHash].cumulativeWeights[responseHash] >
            queries[queryHash].cumulativeWeights[leadingResponseHash]
        ) {
            queries[queryHash].leadingResponse = responseHash;
            emit NewLeadingResponse(
                queryHash,
                leadingResponseHash,
                responseHash
            );
        }
        // hook for updating fee manager on each response
        feeManager.onResponse(
            queryHash,
            respondent,
            responseHash,
            weightToAssign
        );
    }

    /**
     * @notice Used for finalizing the outcome of the query associated with the queryHash
     */
    function finalizeQuery(bytes32 queryHash) external {
        // make sure queryHash is valid
        require(queriesCreated[queryHash] != 0, "invalid queryHash");

        // make sure query period has ended
        require(
            block.timestamp >= _queryExpiry(queryHash),
            "query period ongoing"
        );

        // check that query has not already been finalized,
        // query.outcome is always initialized as 0x0 and set after finalization
        require(
            queries[queryHash].outcome == bytes32(0),
            "duplicate finalization request"
        );

        // record the leading response as the final outcome and emit an event
        bytes32 outcome = queries[queryHash].leadingResponse;
        queries[queryHash].outcome = outcome;
        emit QueryFinalized(
            queryHash,
            outcome,
            queries[queryHash].totalCumulativeWeight
        );
    }

    /// @notice returns the outcome of the query associated with the queryHash
    function getQueryOutcome(bytes32 queryHash)
        external
        view
        returns (bytes32)
    {
        return queries[queryHash].outcome;
    }

    /// @notice returns the duration of time for which an operator can respond to a query
    function getQueryDuration() external view override returns (uint256) {
        return queryDuration;
    }

    /// @notice returns the time when the query, associated with queryHash, was created
    function getQueryCreationTime(bytes32 queryHash)
        external
        view
        override
        returns (uint256)
    {
        return queriesCreated[queryHash];
    }

    function _queryExpiry(bytes32 queryHash) internal view returns (uint256) {
        return queriesCreated[queryHash] + queryDuration;
    }

    // proxy to fee payer contract
    function _delegate(address implementation) internal virtual {
        uint256 value = msg.value;
        //check that the first 32 bytes of calldata match the msg.sender of the call
        uint160 sender;
        assembly {
            //address is 160 bits (256-96), beginning after 16 bytes -- 4 for function sig + 12 for padding in abi.encode
            sender := shr(96, calldataload(16))
        }
        require(address(sender) == msg.sender, "sender != msg.sender");
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())
            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := call(
                gas(), //rest of gas
                implementation, //To addr
                value, //send value
                0, // Inputs are at location x
                calldatasize(), //send calldata
                0, //Store output over input
                0
            ) //Output is 32 bytes long

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
        
    }

    function _fallback() internal virtual {
        _delegate(address(feeManager));
    }

    fallback() external payable virtual {
        _fallback();
    }

    receive() external payable virtual {
        _fallback();
    }

    /// @notice sets the fee manager for the middleware's query manager
    function setFeeManager(IFeeManager _feeManager) external onlyTimelock {
        feeManager = _feeManager;
    }

    /// @notice sets the registration manager for the middleware's query manager
    function setRegistrationManager(IRegistrationManager _registrationManager) external onlyTimelock {
        registrationManager = _registrationManager;
    }

    /// @notice sets the vote weigher for the middleware's query manager
    function setVoteWeigher(IVoteWeigher _voteWeigher) external onlyTimelock {
        _setVoteWeigher(_voteWeigher);
    }

    function _setVoteWeigher(IVoteWeigher _voteWeigher) internal {
        voteWeigher = _voteWeigher;
    }

    function getOpertorCount() public view returns (uint32) {
        return uint32(operatorCounts);
    }

    function getOpertorCountOfType(uint8 operatorType)
        public
        view
        returns (uint32)
    {
        return uint32(operatorCounts >> (operatorType * 32 + 32));
    }
}
