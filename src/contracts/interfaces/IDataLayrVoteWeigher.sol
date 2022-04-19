// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDataLayrVoteWeigher {
    function stakeHashes(uint48) external returns(bytes32);

    function getStakesHashUpdate(uint256 index) external returns(uint256);
    
    function getStakesHashUpdateAndCheckIndex(uint256 index, uint48 dumpNumber) external returns(bytes32);

    function setLatestTime(uint32) external;

    function getOperatorId(address) external returns (uint32);

    function getOperatorFromDumpNumber(address) external view returns (uint48);

    function getOperatorType(address operator) external view returns (uint8);
}
