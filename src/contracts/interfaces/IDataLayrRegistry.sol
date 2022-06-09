// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDataLayrRegistry {
    struct OperatorStake {
        uint32 updateBlockNumber;
        uint32 nextUpdateBlockNumber;
        uint96 ethStake;
        uint96 eigenStake;
    }

    function setLatestTime(uint32 _latestTime) external;

    function getOperatorId(address operator) external returns (uint32);

    function getOperatorFromDumpNumber(address operator) external view returns (uint32);
        
    function getOperatorPubkeyHash(address operator) external view returns (bytes32);

    function getOperatorType(address operator) external view returns (uint8);

    function getStakeFromPubkeyHashAndIndex(bytes32 pubkeyHash, uint256 index) external view returns (OperatorStake memory);

    function getCorrectApkHash(uint256 index, uint32 blockNumber) external returns(bytes32);

    function getLengthOfTotalStakeHistory() external view returns (uint256);
    
    function getTotalStakeFromIndex(uint256 index) external view returns (OperatorStake memory);

    function getOperatorIndex(address operator, uint32 dumpNumber, uint32 index) external view returns (uint32);

    function getTotalOperators(uint32 dumpNumber, uint32 index) external view returns (uint32);
}
