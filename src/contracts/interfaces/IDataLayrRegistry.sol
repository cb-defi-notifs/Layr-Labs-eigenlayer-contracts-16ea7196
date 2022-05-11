// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDataLayrRegistry {

    /**
     @notice used for recording the event whenever DataLayr operator stakes for the first time or updates its stake.
             Primarily used in DataLayrRegistry.sol
     */
    struct OperatorStake {
        // dump number where this stake was updated
        uint32 dumpNumber;

        // dump nuber where next update to the stake happened
        uint32 nextUpdateDumpNumber;

        // updated ETH stake
        uint96 ethStake;

        // updated Eigen stake
        uint96 eigenStake;
    }


    function setLatestTime(uint32) external;

    function getOperatorId(address) external returns (uint32);

    function getDumpNumberOfOperator(address) external view returns (uint32);
        
    function getOperatorPubkeyHash(address) external view returns (bytes32);

    function getOperatorType(address operator) external view returns (uint8);

    function getStakeFromPubkeyHashAndIndex(bytes32, uint256) external view returns (OperatorStake memory);

    function getCorrectApkHash(uint256, uint32) external returns(bytes32);

    function getLengthOfTotalStakeHistory() external view returns (uint256);
    
    function getTotalStakeFromIndex(uint256 index) external view returns (OperatorStake memory);
}
