// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/MiddlewareInterfaces.sol";
import "../interfaces/CoreInterfaces.sol";

abstract contract QueryManager is IQueryManager {
    struct Query {
		//hash(reponse) with the greatest cumulative weight
		bytes32 leadingResponse;
		//hash(finalized response). initialized as 0x0, updated if/when query is finalized
		bytes32 outcome;
		//sum of all cumulative weights
		uint256 totalCumulativeWeight;
		//hash(response) => cumulative weight
		mapping(bytes32 => uint256) cumulativeWeights;
		//operator => hash(response)
		mapping(address => bytes32) responses;
		//operator => weight
		mapping(address => uint256) operatorWeights;
	}
	//fixed duration of all new queries
	uint256 public queryDuration;
	//called when new queries are created. handles payments for queries.
	IFeeManager public feeManager;
	//called when responses are provided by operators
	IVoteWeighter public voteWeighter;
	//hash(queryData) => Query
	mapping(bytes32 => Query) public queries;
	//hash(queryData) => time query created
	mapping(bytes32 => uint256) public queriesCreated;
    bytes32[] public activeQueries;

	event QueryCreated(bytes32 indexed queryDataHash, uint256 blockTimestamp);
	event ResponseReceived(address indexed submitter, bytes32 indexed queryDataHash, bytes32 indexed responseHash, uint256 weightAssigned);
	event NewLeadingResponse(bytes32 indexed queryDataHash, bytes32 indexed previousLeadingResponseHash, bytes32 indexed newLeadingResponseHash);
	event QueryFinalized(bytes32 indexed queryDataHash, bytes32 indexed outcome, uint256 totalCumulativeWeight);

	constructor(uint256 _queryDuration, IFeeManager _feeManager, IVoteWeighter _voteWeighter) {
		queryDuration = _queryDuration;
		feeManager = _feeManager;
		voteWeighter = _voteWeighter;
	}

	function createNewQuery(bytes calldata queryData) external {
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

	function respondToQuery(bytes32 queryHash, bytes calldata response) external {
		address msgSender = msg.sender;
		//make sure query is open and sender has not already responded to it
		require(block.timestamp < _queryExpiry(queryHash), "query period over");
		require(queries[queryHash].operatorWeights[msgSender] == 0, "duplicate response to query");
		//find sender's weight and the hash of their response
		uint256 weightToAssign = voteWeighter.weightOfDelegate(msgSender);
		bytes32 responseHash = keccak256(response);
		//update Query struct with sender's weight + response
		queries[queryHash].operatorWeights[msgSender] = weightToAssign;
		queries[queryHash].responses[msgSender] = responseHash;
		queries[queryHash].cumulativeWeights[responseHash] += weightToAssign;
		queries[queryHash].totalCumulativeWeight += weightToAssign;
		//emit event for response
		emit ResponseReceived(msgSender, queryHash, responseHash, weightToAssign);
		//check if leading response has changed. if so, update leadingResponse and emit an event
		bytes32 leadingResponseHash = queries[queryHash].leadingResponse;
		if (responseHash != leadingResponseHash && queries[queryHash].cumulativeWeights[responseHash] > queries[queryHash].cumulativeWeights[leadingResponseHash]) {
			queries[queryHash].leadingResponse = responseHash;
			emit NewLeadingResponse(queryHash, leadingResponseHash, responseHash);
		}
		//hook for updating fee manager on each response
		feeManager.onResponse(queryHash, msgSender, responseHash, weightToAssign);
	}

	function finalizeQuery(bytes32 queryHash) external {
		//make sure queryHash is valid + query period has ended
		require(queriesCreated[queryHash] != 0, "invalid queryHash");
		require(block.timestamp >= _queryExpiry(queryHash), "query period ongoing");
		//check that query has not already been finalized
		require(queries[queryHash].outcome == bytes32(0), "duplicate finalization request");
		//record final outcome + emit an event
		bytes32 outcome = queries[queryHash].leadingResponse;
		queries[queryHash].outcome = outcome;
		emit QueryFinalized(queryHash, outcome, queries[queryHash].totalCumulativeWeight);
	}

    function getQueryDuration() external view returns(uint256) {
        return queryDuration;
    }

    function getQueryCreationTime(bytes32 queryHash) external view returns(uint256) {
        return queriesCreated[queryHash];
    }

	function _queryExpiry(bytes32 queryHash) internal view returns(uint256) {
		return queriesCreated[queryHash] + queryDuration;
	}
}