// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IRegistry.sol";

/**
 * @title Interface for a `Registry`-type contract that uses either 1 or 2 quorums.
 * @author Layr Labs, Inc.
 * @notice This contract does not currently support n-quorums where n >= 3.
 * Note in particular the presence of only `firstQuorumStake` and `secondQuorumStake` in the `OperatorStake` struct.
 */
interface IQuorumRegistry is IRegistry {
    // DATA STRUCTURES
    enum Status
    {
        // default is inactive
        INACTIVE,
        ACTIVE
    }

    /**
     * @notice  Data structure for storing info on operators to be used for:
     * - sending data by the sequencer
     * - payment and associated challenges
     */
    struct Operator {
        // hash of pubkey of the operator
        bytes32 pubkeyHash;
        // id is always unique
        uint32 id;
        // corresponds to position in operatorList
        uint32 index;
        // start taskNumber from which the  operator has been registered
        uint32 fromTaskNumber;
        // start block from which the  operator has been registered
        uint32 fromBlockNumber;
        // UTC time until which this operator is supposed to serve its obligations to this middleware
        // set only when committing to deregistration
        uint32 serveUntil;
        // UTC time at which the operator deregistered. If set to zero then the operator has not deregistered.
        uint32 deregisterTime;
        // indicates whether the operator is actively registered for serving the middleware or not
        Status status;
    }

    // struct used to give definitive ordering to operators at each blockNumber
    struct OperatorIndex {
        // blockNumber number at which operator index changed
        // note that the operator's index is different *for this block number*, i.e. the *new* index is *inclusive* of this value
        uint32 toBlockNumber;
        // index of the operator in array of operators, or the total number of operators if in the 'totalOperatorsHistory'
        uint32 index;
    }

    struct OperatorStake {
        uint32 updateBlockNumber;
        uint32 nextUpdateBlockNumber;
        uint96 firstQuorumStake;
        uint96 secondQuorumStake;
    }

    function getLengthOfTotalStakeHistory() external view returns (uint256);

    function getTotalStakeFromIndex(uint256 index) external view returns (OperatorStake memory);

    function getOperatorId(address operator) external returns (uint32);

    function getOperatorPubkeyHash(address operator) external view returns (bytes32);

    function getFromTaskNumberForOperator(address operator) external view returns (uint32);

    function getFromBlockNumberForOperator(address operator) external view returns (uint32);

    function getStakeFromPubkeyHashAndIndex(bytes32 pubkeyHash, uint256 index)
        external
        view
        returns (OperatorStake memory);

    function getOperatorIndex(address operator, uint32 blockNumber, uint32 index) external view returns (uint32);

    function getTotalOperators(uint32 blockNumber, uint32 index) external view returns (uint32);

    function numOperators() external view returns (uint32);

    function getOperatorDeregisterTime(address operator) external view returns (uint256);

    function operatorStakes(address operator) external view returns (uint96, uint96);

    function totalStake() external view returns (uint96, uint96);
}
