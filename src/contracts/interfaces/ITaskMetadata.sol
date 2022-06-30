// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface ITaskMetadata {
    function getTaskAndBlockNumberFromTaskHash(bytes32 taskHash) external returns(uint32, uint32);
}