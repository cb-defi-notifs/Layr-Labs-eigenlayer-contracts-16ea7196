// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/IInvestmentStrategy.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IQueryManager.sol";
import "../interfaces/IRegistrationManager.sol";
import "../utils/Initializable.sol";
import "./storage/QueryManagerStorage.sol";

//TODO: upgrading multisig for fee manager and registration manager
//TODO: these should be autodeployed when this is created, allowing for nfgt and eth
/**
 * @notice
 */
contract QueryManager is Initializable, QueryManagerStorage {
    //called when responses are provided by operators
    IVoteWeighter public immutable voteWeighter;

    // EVENTS
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

    constructor(IVoteWeighter _voteWeighter) {
        voteWeighter = _voteWeighter;
    }

    function initialize(
        uint256 _queryDuration,
        uint256 _consensusLayerEthToEth,
        IFeeManager _feeManager,
        address _registrationManager,
        address _timelock,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager
    ) external initializer {
        queryDuration = _queryDuration;
        consensusLayerEthToEth = _consensusLayerEthToEth;
        feeManager = _feeManager;
        registrationManager = _registrationManager;
        timelock = _timelock;
        delegation = _delegation;
        investmentManager = _investmentManager;
    }

    /**
     * @notice Used by an operator to de-register itself from providing service to the middleware.
     */
    // CRITIC: (1) Currently, from DL perspective, this data parameter seems unused. Are we still
    //          envisioning it as an input opType?
    //         (2) Why is deregister a payable type? Whom are you paying for deregistering and why?
    //         (3) Seems like an operator can deregister before requiring its delegators to withdraw
    //             their respective pending rewards. Is this a concern?
    function deregister(bytes calldata data) external payable {
        require(
            operatorType[msg.sender] != 0,
            "Registrant is not registered with this middleware."
        );
        require(
            IRegistrationManager(registrationManager).deregisterOperator(
                msg.sender,
                data
            ),
            "Deregistration not permitted"
        );

        //subtract the deregisterers stake from the total
        totalStake.eigenStaked -= operatorStakes[msg.sender].eigenStaked;
        totalStake.ethStaked -= operatorStakes[msg.sender].ethStaked;
        //clear the deregisterers stake
        operatorStakes[msg.sender].eigenStaked = 0;
        operatorStakes[msg.sender].ethStaked = 0;

        /**
         * @dev Referring to the detailed explanation on structure of operatorCounts in
         *      QueryManagerStorage.sol, in order to subtract the number of operators
         *      of i^th type, first left shift 1 by 32*i bits and subtract it from <n_i>.
         *      Then, subtract 1 from <n> to decrement the number of total operators.
         */
        operatorCounts =
            (operatorCounts - (1 << (32 * operatorType[msg.sender]))) -
            1;

        // the operator is recorded as being no longer active
        operatorType[msg.sender] = 0;
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
     * @dev Calls the RegistrationManager contract.
     */
    function register(bytes calldata data) external payable {
        require(
            operatorType[msg.sender] == 0,
            "Registrant is already registered"
        );

        /**
         * This function calls the registerOperator function of the middleware to process the
         * data that has been provided by the operator.
         */
        (uint8 opType, uint128 eigenAmount) = IRegistrationManager(
            registrationManager
        ).registerOperator(msg.sender, data);

        // record the operator type of the operator
        operatorType[msg.sender] = opType;

        /**
         * get details on the delegators of the operator that has called this function
         * for registration with the middleware
         */
        //SHOULD BE LESS THAN 2^128, do we need to switch everything to uint128? @TODO
        uint128 ethAmount = uint128(
            delegation.getUnderlyingEthDelegated(msg.sender) +
                delegation.getConsensusLayerEthDelegated(msg.sender) /
                consensusLayerEthToEth
        );

        //only 1 SSTORE
        operatorStakes[msg.sender] = Stake(eigenAmount, ethAmount);

        /**
         * total Eigen being employed by the operator for securing the queries
         * from middleware via EigenLayr
         */
        //i think this gets batched as 1 SSTORE @TODO check
        totalStake.eigenStaked += eigenAmount;
        totalStake.ethStaked += ethAmount;

        operatorCounts = (operatorCounts + (1 << (32 * opType))) + 1;
    }

    /**
     * @notice This function can be called by anyone to update the assets that have been
     *         deposited by the specified operator for validation of middleware.
     */
    /**
     * @return
     */
    function updateStake(address operator)
        public
        override
        returns (uint128, uint128)
    {
        // get new eigen and eth amounts
        uint128 newEigen = voteWeighter.weightOfOperatorEigen(operator);
        uint128 newEth = uint128(
            delegation.getUnderlyingEthDelegated(msg.sender) +
                delegation.getConsensusLayerEthDelegated(msg.sender) /
                consensusLayerEthToEth
        );
        //store old stake in memory
        uint128 prevEigen = operatorStakes[msg.sender].eigenStaked;
        uint128 prevEth = operatorStakes[msg.sender].ethStaked;

        //store the new stake
        operatorStakes[msg.sender].eigenStaked = newEigen;
        operatorStakes[msg.sender].ethStaked = newEth;

        //subtract the deregisterers stake from the total
        totalStake.eigenStaked = totalStake.eigenStaked + newEigen - prevEigen;
        totalStake.ethStaked = totalStake.ethStaked + newEth - prevEth;
        //return CLE, Eth shares, Eigen
        return (newEth, newEigen);
    }

    //get value of shares and add consensus layr eth weighted by whatever proportion the middlware desires
    function totalEthStaked() public view returns (uint128) {
        return totalStake.ethStaked;
    }

    function totalEigenStaked() public view returns (uint128) {
        return totalStake.eigenStaked;
    }

    //get value of shares and add consensus layr eth weighted by whatever proportion the middlware desires
    function ethStakedByOperator(address operator)
        public view
        returns (uint128)
    {
        return operatorStakes[operator].ethStaked;
    }

    function eigenStakedByOperator(address operator)
        public
        view
        returns (uint128)
    {
        return operatorStakes[operator].eigenStaked;
    }

    function ethAndEigenStakedForOperator(address operator)
        public view
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
        address msgSender = msg.sender;
        bytes32 queryDataHash = keccak256(queryData);
        //verify that query has not already been created
        require(queriesCreated[queryDataHash] == 0, "duplicate query");
        //mark query as created and emit an event
        queriesCreated[queryDataHash] = block.timestamp;
        emit QueryCreated(queryDataHash, block.timestamp);
        //hook to manage payment for query
        IFeeManager(feeManager).payFee(msgSender);
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
        address msgSender = msg.sender;
        //make sure query is open and sender has not already responded to it
        require(block.timestamp < _queryExpiry(queryHash), "query period over");
        require(
            queries[queryHash].operatorWeights[msgSender] == 0,
            "duplicate response to query"
        );
        //find sender's weight and the hash of their response
        uint256 weightToAssign = voteWeighter.weightOfOperatorEth(msgSender);
        bytes32 responseHash = keccak256(response);
        //update Query struct with sender's weight + response
        queries[queryHash].operatorWeights[msgSender] = weightToAssign;
        queries[queryHash].responses[msgSender] = responseHash;
        queries[queryHash].cumulativeWeights[responseHash] += weightToAssign;
        queries[queryHash].totalCumulativeWeight += weightToAssign;
        //emit event for response
        emit ResponseReceived(
            msgSender,
            queryHash,
            responseHash,
            weightToAssign
        );
        //check if leading response has changed. if so, update leadingResponse and emit an event
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
        //hook for updating fee manager on each response
        feeManager.onResponse(
            queryHash,
            msgSender,
            responseHash,
            weightToAssign
        );
    }

    function finalizeQuery(bytes32 queryHash) external {
        //make sure queryHash is valid + query period has ended
        require(queriesCreated[queryHash] != 0, "invalid queryHash");
        require(
            block.timestamp >= _queryExpiry(queryHash),
            "query period ongoing"
        );
        //check that query has not already been finalized
        require(
            queries[queryHash].outcome == bytes32(0),
            "duplicate finalization request"
        );
        //record final outcome + emit an event
        bytes32 outcome = queries[queryHash].leadingResponse;
        queries[queryHash].outcome = outcome;
        emit QueryFinalized(
            queryHash,
            outcome,
            queries[queryHash].totalCumulativeWeight
        );
    }

    function getQueryOutcome(bytes32 queryHash)
        external
        view
        returns (bytes32)
    {
        return queries[queryHash].outcome;
    }

    function getQueryDuration() external view override returns (uint256) {
        return queryDuration;
    }

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

    function setFeeManager(IFeeManager _feeManager) external {
        require(msg.sender == timelock, "onlyTimelock");
        feeManager = _feeManager;
    }

    function setTimelock(address _timelock) external {
        require(msg.sender == timelock, "onlyTimelock");
        timelock = _timelock;
    }
}
