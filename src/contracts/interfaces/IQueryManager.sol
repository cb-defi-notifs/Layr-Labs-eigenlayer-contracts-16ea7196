// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IFeeManager.sol";
import "./IVoteWeigher.sol";
import "../interfaces/ITimelock_Managed.sol";

interface IQueryManager is ITimelock_Managed {
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

    // struct for storing the amount of Eigen and ETH that has been staked
    struct Stake {
        uint128 eigenStaked;
        uint128 ethStaked;
    }

    function operatorCounts() external view returns(uint256);

    function getOpertorCount() external view returns(uint32);

    function getOpertorCountOfType(uint8) external view returns(uint32);

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
}
