// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDataLayr {
    function initDataStore(
        uint48 dumpNumber,
        bytes32 headerHash,
        uint32 totalBytes,
        uint32 storePeriodLength
    ) external;

    function confirm(
        uint48 dumpNumber,
        bytes32 headerHash,
        uint256 ethStakeSigned,
        uint256 eigenStakeSigned,
        uint256,
        uint256
    ) external;

    function dataStores(bytes32)
        external
        returns (
            uint48,
            uint32,
            uint32,
            bool
        );
}
