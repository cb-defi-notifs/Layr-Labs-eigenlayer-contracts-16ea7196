// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDataLayr {
    function initDataStore(
        uint48 dumpNumber,
        bytes32 ferkleRoot,
        uint32 totalBytes,
        uint32 storePeriodLength
    ) external;

    function confirm(
        uint256 dumpNumber,
        bytes32 ferkleRoot,
        uint256 ethStakeSigned,
        uint256 eigenStakeSigned,
        uint256,
        uint256
    ) external;
}