// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDataLayrVoteWeigher {
    struct OperatorStake {
        uint32 dumpNumber;
        uint32 nextUpdateDumpNumber;
        uint96 ethStake;
        uint96 eigenStake;
    }

    function setLatestTime(uint32) external;

    function getOperatorId(address) external returns (uint32);

    function getOperatorFromDumpNumber(address) external view returns (uint32);
        
    function getOperatorPubkeyHash(address) external view returns (bytes32);

    function getOperatorType(address operator) external view returns (uint8);

    function getStakeFromPubkeyHashAndIndex(bytes32, uint256) external view returns (OperatorStake memory);

    function getCorrectCompressedApk(uint256, uint32) external returns(bytes memory);
}
