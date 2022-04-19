// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "../governance/Timelock.sol";
// import "../interfaces/IInvestmentStrategy.sol";
// import "../interfaces/IInvestmentManager.sol";
// import "../interfaces/IEigenLayrDelegation.sol";
// import "../interfaces/IRepository.sol";
// import "../interfaces/IRegistrationManager.sol";
// import "../utils/Initializable.sol";
// import "./storage/RepositoryStorage.sol";

// // TODO: discuss deprecation of this logic and/or change in specification to support deprecating this.
// abstract contract Repository_Deprecated_Functionality is Initializable, RepositoryStorage {
//     /**
//      * @notice creates a new query based on the @param queryData passed.
//      */
//     function createNewQuery(bytes calldata queryData) external {
//         _createNewQuery(msg.sender, queryData);
//     }

//     function _createNewQuery(address queryCreator, bytes calldata queryData)
//         internal
//     {
//         bytes32 queryDataHash = keccak256(queryData);

//         //verify that query has not already been created
//         require(queriesCreated[queryDataHash] == 0, "duplicate query");

//         //mark query as created and emit an event
//         queriesCreated[queryDataHash] = block.timestamp;
//         emit QueryCreated(queryDataHash, block.timestamp);

//         //hook to manage payment for query
//         IFeeManager(feeManager).payFee(queryCreator);
//     }

//     /**
//      * @notice Used by operators to respond to a specific query.
//      */
//     /**
//      * @param queryHash is the identifier for the query to which the operator is responding,
//      * @param response is the operator's response for the query.
//      */
//     function respondToQuery(bytes32 queryHash, bytes calldata response)
//         external
//     {
//         _respondToQuery(msg.sender, queryHash, response);
//     }

//     function _respondToQuery(
//         address respondent,
//         bytes32 queryHash,
//         bytes calldata response
//     ) internal {
//         // make sure query is open
//         require(block.timestamp < _queryExpiry(queryHash), "query period over");

//         // make sure sender has not already responded to it
//         require(
//             queries[queryHash].operatorWeights[respondent] == 0,
//             "duplicate response to query"
//         );

//         // find respondent's weight and the hash of their response
//         uint256 weightToAssign = voteWeigher.weightOfOperatorEth(respondent);
//         bytes32 responseHash = keccak256(response);

//         // update Query struct with respondent's weight and response
//         queries[queryHash].operatorWeights[respondent] = weightToAssign;
//         queries[queryHash].responses[respondent] = responseHash;
//         queries[queryHash].cumulativeWeights[responseHash] += weightToAssign;
//         queries[queryHash].totalCumulativeWeight += weightToAssign;

//         //emit event for response
//         emit ResponseReceived(
//             respondent,
//             queryHash,
//             responseHash,
//             weightToAssign
//         );

//         // check if leading response has changed. if so, update leadingResponse and emit an event
//         bytes32 leadingResponseHash = queries[queryHash].leadingResponse;
//         if (
//             responseHash != leadingResponseHash &&
//             queries[queryHash].cumulativeWeights[responseHash] >
//             queries[queryHash].cumulativeWeights[leadingResponseHash]
//         ) {
//             queries[queryHash].leadingResponse = responseHash;
//             emit NewLeadingResponse(
//                 queryHash,
//                 leadingResponseHash,
//                 responseHash
//             );
//         }
//         // hook for updating fee manager on each response
//         feeManager.onResponse(
//             queryHash,
//             respondent,
//             responseHash,
//             weightToAssign
//         );
//     }

//     /**
//      * @notice Used for finalizing the outcome of the query associated with the queryHash
//      */
//     function finalizeQuery(bytes32 queryHash) external {
//         // make sure queryHash is valid
//         require(queriesCreated[queryHash] != 0, "invalid queryHash");

//         // make sure query period has ended
//         require(
//             block.timestamp >= _queryExpiry(queryHash),
//             "query period ongoing"
//         );

//         // check that query has not already been finalized,
//         // query.outcome is always initialized as 0x0 and set after finalization
//         require(
//             queries[queryHash].outcome == bytes32(0),
//             "duplicate finalization request"
//         );

//         // record the leading response as the final outcome and emit an event
//         bytes32 outcome = queries[queryHash].leadingResponse;
//         queries[queryHash].outcome = outcome;
//         emit QueryFinalized(
//             queryHash,
//             outcome,
//             queries[queryHash].totalCumulativeWeight
//         );
//     }

//     /// @notice returns the outcome of the query associated with the queryHash
//     function getQueryOutcome(bytes32 queryHash)
//         external
//         view
//         returns (bytes32)
//     {
//         return queries[queryHash].outcome;
//     }

//     /// @notice returns the duration of time for which an operator can respond to a query
//     function getQueryDuration() external view returns (uint256) {
//         return queryDuration;
//     }

//     /// @notice returns the time when the query, associated with queryHash, was created
//     function getQueryCreationTime(bytes32 queryHash)
//         external
//         view
//         returns (uint256)
//     {
//         return queriesCreated[queryHash];
//     }

//     function _queryExpiry(bytes32 queryHash) internal view returns (uint256) {
//         return queriesCreated[queryHash] + queryDuration;
//     }

//     // proxy to fee manager contract
//     function _delegate(address _feeManager) internal virtual {
//         uint256 value = msg.value;
//         //check that the first 32 bytes of calldata match the msg.sender of the call
//         uint160 sender;
//         assembly {
//             //address is 160 bits (256-96), beginning after 16 bytes -- 4 for function sig + 12 for padding in abi.encode
//             sender := shr(96, calldataload(16))
//         }
//         require(address(sender) == msg.sender, "sender != msg.sender");
//         assembly {
//             // Copy msg.data. We take full control of memory in this inline assembly
//             // block because it will not return to Solidity code. We overwrite the
//             // Solidity scratch pad at memory position 0.
//             calldatacopy(0, 0, calldatasize())
//             // Call the feeManager.
//             // out and outsize are 0 because we don't know the size yet.
//             let result := call(
//                 gas(), //rest of gas
//                 _feeManager, //To addr
//                 value, //send value
//                 0, // Inputs are at location x
//                 calldatasize(), //send calldata
//                 0, //Store output over input
//                 0
//             ) //Output is 32 bytes long

//             // Copy the returned data.
//             returndatacopy(0, 0, returndatasize())

//             switch result
//             // delegatecall returns 0 on error.
//             case 0 {
//                 revert(0, returndatasize())
//             }
//             default {
//                 return(0, returndatasize())
//             }
//         }
        
//     }

//     function _fallback() internal virtual {
//         _delegate(address(feeManager));
//     }

//     fallback() external payable virtual {
//         _fallback();
//     }

//     receive() external payable virtual {
//         _fallback();
//     }
// }
