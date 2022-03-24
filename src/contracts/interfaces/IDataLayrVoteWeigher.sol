// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDataLayrVoteWeigher {
    function setLatestTime(uint32) external;

    function getOperatorId(address) external returns (uint32);

    function getOperatorFromDumpNumber(address) external view returns (uint48);
}
