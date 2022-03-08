// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/IQueryManager.sol";
import "../interfaces/IRegistrationManager.sol";

//TODO: upgrading multisig for fee manager and registration manager
contract QueryManager is IQueryManager {
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
	IVoteWeighter public immutable voteWeighter;
	//timelock address which has control over upgrades of feeManager
	address public timelock;
	// number of registrants of this service
	uint256 public numRegistrants;
	//map from registrant address to whether they are active or not
	mapping(address => bool) public isRegistrantActive;
	address public registrationManager;
	//hash(queryData) => Query
	mapping(bytes32 => Query) public queries;
	//hash(queryData) => time query created
	mapping(bytes32 => uint256) public queriesCreated;
    bytes32[] public activeQueries;

	event QueryCreated(bytes32 indexed queryDataHash, uint256 blockTimestamp);
	event ResponseReceived(address indexed submitter, bytes32 indexed queryDataHash, bytes32 indexed responseHash, uint256 weightAssigned);
	event NewLeadingResponse(bytes32 indexed queryDataHash, bytes32 indexed previousLeadingResponseHash, bytes32 indexed newLeadingResponseHash);
	event QueryFinalized(bytes32 indexed queryDataHash, bytes32 indexed outcome, uint256 totalCumulativeWeight);

	constructor(uint256 _queryDuration, IFeeManager _feeManager, IVoteWeighter _voteWeighter, address _registrationManager, address _timelock) {
		queryDuration = _queryDuration;
		feeManager = _feeManager;
		voteWeighter = _voteWeighter;
		registrationManager = _registrationManager;
		timelock = _timelock;
	}

	// decrement number of registrants
	function deregister(bytes calldata data) external payable {
		require(isRegistrantActive[msg.sender], "Registrant is not registered");
		require(IRegistrationManager(registrationManager).operatorPermittedToLeave(msg.sender, data), "registrant not permitted");
		numRegistrants--;
		isRegistrantActive[msg.sender] = false;
    }

	// increment number of registrants
	// call registration contract with given data
    function register(bytes calldata data) external payable {
		require(!isRegistrantActive[msg.sender], "Registrant is already registered");
		require(IRegistrationManager(registrationManager).operatorPermitted(msg.sender, data), "registrant not permitted");
		numRegistrants++;
		isRegistrantActive[msg.sender] = true;
    }

	function getIsRegistrantActive(address operator) public view returns(bool) { 
		return isRegistrantActive[operator];
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
		uint256 weightToAssign = voteWeighter.weightOfOperatorEth(msgSender);
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

	function getQueryOutcome(bytes32 queryHash) external view returns(bytes32) {
        return queries[queryHash].outcome;
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
                            value,    //send value
                            0,    // Inputs are at location x
                            calldatasize(), //send calldata
                            0,    //Store output over input
                            0) //Output is 32 bytes long

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