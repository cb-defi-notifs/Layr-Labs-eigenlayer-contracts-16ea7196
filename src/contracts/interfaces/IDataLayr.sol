// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDataLayr {
    function initDataStore(
        uint48 dumpNumber,
        bytes32 ferkleRoot,
        uint32 totalBytes,
        uint32 storePeriodLength,
        address submitter
    ) external;

    function confirm(
        uint48 dumpNumber,
        bytes32 ferkleRoot,
        address submitter,
        uint256 ethStakeSigned,
        uint256 eigenStakeSigned,
        uint256,
        uint256
    ) external;
}