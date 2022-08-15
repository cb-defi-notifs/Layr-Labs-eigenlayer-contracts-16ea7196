// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IRegistry.sol";

interface IQuorumRegistry is IRegistry {
    // DATA STRUCTURES 
    enum Active {
        // default is inactive
        INACTIVE,
        ACTIVE
    }

    /**
     * @notice  Data structure for storing info on operators to be used for:
     *           - sending data by the sequencer
     *           - payment and associated challenges
     */
    struct Registrant {
        // hash of pubkey of the operator
        bytes32 pubkeyHash;

        // id is always unique
        uint32 id;

        // corresponds to position in registrantList
        uint64 index;

        // start block from which the  operator has been registered
        uint32 fromTaskNumber;
        uint32 fromBlockNumber; 

        // UTC time until which this operator is supposed to serve its obligations to this middleware
        // set only when committing to deregistration
        uint32 serveUntil;

        // indicates whether the operator is actively registered for serving the middleware or not 
        Active active;

        // socket address of the node
        string socket;

        uint256 deregisterTime;
    }

    // struct used to give definitive ordering to operators at each blockNumber
    struct OperatorIndex {
        // blockNumber number at which operator index changed
        // note that the operator's index is different *for this block number*, i.e. the new index is inclusive of this value
        uint32 toBlockNumber;
        // index of the operator in array of operators, or the total number of operators if in the 'totalOperatorsHistory'
        uint32 index;
    }

    struct OperatorStake {
        uint32 updateBlockNumber;
        uint32 nextUpdateBlockNumber;
        uint96 ethStake;
        uint96 eigenStake;
    }

    function getLengthOfTotalStakeHistory() external view returns (uint256);

    function getTotalStakeFromIndex(uint256 index) external view returns (OperatorStake memory);   

    function getOperatorId(address operator) external returns (uint32);

    function getOperatorPubkeyHash(address operator) external view returns (bytes32);

    function getOperatorStatus(address operator) external view returns (Active);

    function getFromTaskNumberForOperator(address operator) external view returns (uint32);

    function getFromBlockNumberForOperator(address operator) external view returns (uint32);

    function getStakeFromPubkeyHashAndIndex(bytes32 pubkeyHash, uint256 index) external view returns (OperatorStake memory);
                
    function getOperatorIndex(address operator, uint32 blockNumber, uint32 index) external view returns (uint32);

    function getTotalOperators(uint32 blockNumber, uint32 index) external view returns (uint32);
    
    function getOperatorDeregisterTime(address operator) external view returns (uint256);

    function operatorStakes(address operator) external view returns (uint96, uint96);

    function totalStake() external view returns (uint96, uint96);

    function totalEthStaked() external view returns (uint96);

    function totalEigenStaked() external view returns (uint96);
}
