// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDataLayrVoteWeigher {
    function eigenStakeHashes(uint48) external returns(bytes32);
    function ethStakeHashes(uint48) external returns(bytes32);
    function getEthStakesHashUpdate(uint256 index) external returns(uint256);
    function getEigenStakesHashUpdate(uint256 index) external returns(uint256);
    
    function getEthStakesHashUpdateAndCheckIndex(uint256 index, uint48 dumpNumber) external returns(bytes32);
    function getEigenStakesHashUpdateAndCheckIndex(uint256 index, uint48 dumpNumber) external returns(bytes32);

    function setLatestTime(uint32) external;

    function getOperatorId(address) external returns (uint32);

    function getOperatorFromDumpNumber(address) external view returns (uint48);
}
