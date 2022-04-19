// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IFeeManager.sol";
import "./IVoteWeigher.sol";
import "../interfaces/ITimelock_Managed.sol";

interface IQueryManager is ITimelock_Managed {
    // STRUCTS
    // struct for storing the amount of Eigen and ETH that has been staked
    struct Stake {
        uint128 ethStaked;
        uint128 eigenStaked;
    }

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
    
    // EVENTS
    event Registration(address indexed operator);
    event Deregistration(address indexed operator);
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

    function consensusLayerEthToEth() external view returns (uint256);

    function totalEigenStaked() external view returns (uint128);

    function createNewQuery(bytes calldata) external;

    function getQueryDuration() external view returns (uint256);

    function getQueryCreationTime(bytes32) external view returns (uint256);

    function getOperatorType(address) external view returns (uint8);

    function numRegistrants() external view returns (uint256);

    function voteWeigher() external view returns (IVoteWeigher);

    function feeManager() external view returns (IFeeManager);

    function updateStake(address)
        external
        returns (
            uint128,
            uint128
        );

    function eigenStakedByOperator(address) external view returns (uint128);

    function ethStakedByOperator(address) external view returns (uint128);

    function totalEthStaked() external view returns (uint128);

    function ethAndEigenStakedForOperator(address)
        external
        view returns (uint128, uint128);

    function operatorStakes(address) external view returns (uint128, uint128);

    function totalStake() external view returns (uint128, uint128);

    function register(bytes calldata data) external;

    function deregister(bytes calldata data) external;

    function pushStakeUpdate(address operator, uint96 ethAmount, uint96 eigenAmount) external;
}
