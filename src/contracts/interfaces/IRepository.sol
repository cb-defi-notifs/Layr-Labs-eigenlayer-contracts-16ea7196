// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IServiceManager.sol";
import "./IVoteWeigher.sol";
import "./IRegistrationManager.sol";
import "../interfaces/ITimelock_Managed.sol";

interface IRepository is ITimelock_Managed {
//     /**
//      * @notice This struct is used for containing the details of a query that is created 
//      *         by the middleware for validation in EigenLayr.
//      */
// // TODO: move some of this commented out struct into the proper new interface spec?
//     struct Query {
//         // hash(reponse) with the greatest cumulative weight
//         bytes32 leadingResponse;
//         // hash(finalized response). initialized as 0x0, updated if/when query is finalized
//         bytes32 outcome;
//         // sum of all cumulative weights
//         uint256 totalCumulativeWeight;
//         // hash(response) => cumulative weight
//         mapping(bytes32 => uint256) cumulativeWeights;
//         // operator => hash(response)
//         mapping(address => bytes32) responses;
//         // operator => weight
//         mapping(address => uint256) operatorWeights;
//     }
    
// TODO: move some of these commented out events into the proper new interface spec(s)?
    // event Registration(address indexed operator);
    // event Deregistration(address indexed operator);
    // event QueryCreated(bytes32 indexed queryDataHash, uint256 blockTimestamp);
    // event ResponseReceived(
    //     address indexed submitter,
    //     bytes32 indexed queryDataHash,
    //     bytes32 indexed responseHash,
    //     uint256 weightAssigned
    // );
    // event NewLeadingResponse(
    //     bytes32 indexed queryDataHash,
    //     bytes32 indexed previousLeadingResponseHash,
    //     bytes32 indexed newLeadingResponseHash
    // );
    // event QueryFinalized(
    //     bytes32 indexed queryDataHash,
    //     bytes32 indexed outcome,
    //     uint256 totalCumulativeWeight
    // );

// TODO: move some of these commented out functions into the proper new interface spec(s)?
    // function createNewQuery(bytes calldata) external;

    // function getQueryDuration() external view returns (uint256);

    // function getQueryCreationTime(bytes32) external view returns (uint256);

    function voteWeigher() external view returns (IVoteWeigher);

    function ServiceManager() external view returns (IServiceManager);

    function registrationManager() external view returns (IRegistrationManager);
}