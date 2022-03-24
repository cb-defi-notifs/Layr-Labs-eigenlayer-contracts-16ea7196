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
        IFeeManager _feeManager,
        address _registrationManager,
        address _timelock,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager
    ) external initializer {
        queryDuration = _queryDuration;
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


        /**
         * get the total eigen that was being used by operator to provide service to middleware.
         * This total eigen comprises of operator's own Eigen and the Eigen that had been delegated
         * to it by its delegators. 
         */
        uint256 eigenDepositedByDeregisterer = eigenDeposited[msg.sender];
        if (eigenDepositedByDeregisterer != 0) {
            /** 
             * deduct this eigen from total eigen that has been staked to validate the
             * middleware's queries
             */
            totalEigen -= eigenDepositedByDeregisterer;
        }
        eigenDeposited[msg.sender] = 0;


        // update shares due to the de-registration by the operator
        uint256 stratsLength = operatorStrats[msg.sender].length;
        for (uint i = 0; i < stratsLength; ) {
            //TODO: REMOVE FROM STRATS IF SHARES ARE NOW 0
            /**  
            *  Due to the operator de-registering from providing service to the middleware,
            *  update total shares for the investment strategies that are 
            *  being utilized by any of the delegator of that operator.
            */
            shares[operatorStrats[msg.sender][i]] -= operatorShares[msg.sender][
                operatorStrats[msg.sender][i]
            ];
            /**
             * TBA.  
             */
            operatorShares[msg.sender][operatorStrats[msg.sender][i]] = 0;
            unchecked {
                ++i;
            }
        }

        // sets operator to have no strats
        operatorStrats[msg.sender] = new IInvestmentStrategy[](0);

        /**  
         * deduct the ETH that was staked into settlement layer from the operator and its associated
         * delegators from the total ETH
         */
        totalConsensusLayerEth -= consensusLayerEth[msg.sender];

        /** 
         * record amount of ETH from the operator and its delegators that is being used for providing
         * service to middleware as 0
         */
        consensusLayerEth[msg.sender] = 0;

        //subtract 1 from the correct type count and 1 from the total count (last 32 bits)
        //shift is 32 bytes for the total count and 32 bytes for every type count the needs to be skipped
        // CRITIC: not clear to me what is it. Explanation in slack please?
        operatorCounts = (operatorCounts - (1 << 32*operatorType[msg.sender])) - 1;
        operatorType[msg.sender] = 0;
    }


    // call registration contract with given data
    /**
     * @notice Used by an operator to register itself for providing service to the middleware
     *         associated with this QueryManager contract.
     */
    /**
     * @param data is an encoding of the operatorType that the operator wants to register as 
     *        with the middleware, infrastructure details that the middleware would need for 
     *        coordinating with the operator to elicit its response, etc. The details may 
     *        vary from middleware to middleware. 
     */ 
    function register(bytes calldata data) external payable {
        require(
            operatorType[msg.sender] == 0,
            "Registrant is already registered"
        );

        /**
         * This function calls the registerOperator function of the middleware to process the
         * data that has been provided by the operator. This function is required under
         * the interface IRegistrationManager.
         */
        (uint8 opType, uint256 eigenAmount) = IRegistrationManager(
            registrationManager
        ).registerOperator(msg.sender, data);

        operatorType[msg.sender] = opType;
        
        // total Eigen that has been employed by the operator for providing validation service 
        // to this middleware. 
        eigenDeposited[msg.sender] = eigenAmount;

        // total Eigen being employed for securing the queries from middleware via EigenLayr
        totalEigen += eigenAmount;

        (
            IInvestmentStrategy[] memory delegatedOperatorStrats,
            uint256[] memory delegatedOperatorShares,
            uint256 delegatedConsensusLayerEth
        ) = delegation.getControlledEthStake(msg.sender);

        uint256 stratsLength = delegatedOperatorStrats.length;
        for (uint i = 0; i < stratsLength; ) {
            if (shares[delegatedOperatorStrats[i]] == 0) {
                strats.push(delegatedOperatorStrats[i]);
            }
            shares[delegatedOperatorStrats[i]] += delegatedOperatorShares[i];
            unchecked {
                ++i;
            }
        }
        operatorStrats[msg.sender] = delegatedOperatorStrats;

        totalConsensusLayerEth += delegatedConsensusLayerEth;
        consensusLayerEth[msg.sender] = delegatedConsensusLayerEth;
        //add 1 to the correct type count and 1 to the total count (last 32 bits)
        //shift is 32 bytes for the total count and 32 bytes for every type count the needs to be skipped
        operatorCounts = (operatorCounts - (1 << 32*opType)) - 1;
    }

    function updateStake(address operator)
        public
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        //get new eigen amount and replace it
        uint256 newEigen = voteWeighter.weightOfOperatorEigen(operator);
        totalEigen = totalEigen + newEigen - eigenDeposited[operator];
        eigenDeposited[operator] = newEigen;
        //get new delegated shares
        (
            IInvestmentStrategy[] memory delegatedOperatorStrats,
            uint256[] memory delegatedOperatorShares,
            uint256 delegatedConsensusLayerEth
        ) = delegation.getControlledEthStake(operator);
        //get current strategies
        IInvestmentStrategy[] memory operatorStratsPrev = operatorStrats[
            operator
        ];
        uint256 stratsRemaining = operatorStratsPrev.length;
        uint256 stratsLength = delegatedOperatorStrats.length;
        for (uint i = 0; i < stratsLength; ) {
            uint256 qmShares = shares[delegatedOperatorStrats[i]];
            //if first time seeing
            if (qmShares == 0) {
                strats.push(delegatedOperatorStrats[i]);
            }
            //add new shares
            qmShares += delegatedOperatorShares[i];
            //loop throuw all old strategies that havent matched the one's we have seen yet
            for (uint j = 0; j < stratsRemaining; ) {
                //check if new strategy matches an old one
                if (delegatedOperatorStrats[i] == operatorStratsPrev[j]) {
                    //subtract old shares, modify memory (looping) array
                    qmShares -= operatorShares[operator][operatorStratsPrev[j]];
                    //bring last unchecked strategies
                    operatorStratsPrev[j] = operatorStratsPrev[
                        (stratsRemaining - 1)
                    ];
                    //1 less strat remains
                    --stratsRemaining;
                    break;
                }
                unchecked {
                    ++i;
                }
            }
            //update shares in storage
            shares[delegatedOperatorStrats[i]] = qmShares;
            //update operator shares in storage
            operatorShares[operator][
                delegatedOperatorStrats[i]
            ] = delegatedOperatorShares[i];
            unchecked {
                ++i;
            }
        }

        //set shares to zero for old strategies that aren't still present
        for (uint i = 0; i < stratsRemaining; ) {
            operatorShares[operator][operatorStratsPrev[i]] = 0;
            unchecked {
                ++i;
            }
        }
        //update operator strats in storage
        operatorStrats[operator] = delegatedOperatorStrats;
        //update consensusLayrEth
        totalConsensusLayerEth =
            totalConsensusLayerEth +
            delegatedConsensusLayerEth -
            consensusLayerEth[operator];
        consensusLayerEth[operator] = delegatedConsensusLayerEth;
        //return CLE, Eth shares, Eigen
        return (
            delegatedConsensusLayerEth,
            investmentManager.getUnderlyingEthOfStrategyShares(
                delegatedOperatorStrats,
                delegatedOperatorShares
            ),
            newEigen
        );
    }

    function totalEthValueOfShares() public returns (uint256) {
        uint256[] memory sharesList = new uint256[](strats.length);
        for (uint256 i = 0; i < sharesList.length; i++) {
            sharesList[i] = shares[strats[i]];
        }
        return
            investmentManager.getUnderlyingEthOfStrategyShares(
                strats,
                sharesList
            );
    }

    function totalEthValueOfSharesForOperator(address operator)
        public
        returns (uint256)
    {
        uint256[] memory operatorSharesList = new uint256[](
            operatorStrats[operator].length
        );
        for (uint256 i = 0; i < operatorSharesList.length; i++) {
            operatorSharesList[i] = operatorShares[operator][
                operatorStrats[operator][i]
            ];
        }
        return
            investmentManager.getUnderlyingEthOfStrategyShares(
                operatorStrats[operator],
                operatorSharesList
            );
    }

    //get value of shares and add consensus layr eth weighted by whatever proportion the middlware desires
    function totalEthStaked() public returns (uint256) {
        return
            totalEthValueOfShares() +
            totalConsensusLayerEth /
            consensusLayerEthToEth;
    }

    //get value of shares and add consensus layr eth weighted by whatever proportion the middlware desires
    function totalEthValueStakedForOperator(address operator)
        public
        returns (uint256)
    {
        return
            totalEthValueOfSharesForOperator(operator) +
            totalConsensusLayerEth /
            consensusLayerEthToEth;
    }

    function eigenDepositedByOperator(address operator)
        public
        view
        returns (uint256)
    {
        return eigenDeposited[operator];
    }

    function totalEthValueStakedAndEigenForOperator(address operator)
        public
        returns (uint256, uint256)
    {
        return (totalEthValueStakedForOperator(operator), eigenDeposited[operator]);
    }

    function consensusLayrEthOfOperator(address operator)
        public
        view
        returns (uint256)
    {
        return consensusLayerEth[operator];
    }

    function getOperatorType(address operator)
        public
        view
        override
        returns (uint8)
    {
        return operatorType[operator];
    }


    /**
     * @notice 
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
