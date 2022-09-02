// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9.0;

import "./ITaskMetadata.sol";

interface IDataLayr is ITaskMetadata {
    function initDataStore(
        uint32 dataStoreId,
        bytes32 headerHash,
        uint32 totalBytes,
        uint32 storePeriodLength,
        uint32 stakesBlockNumber,
        bytes calldata header
    ) external;

    function confirm(
        uint32 dataStoreId,
        bytes32 headerHash,
        uint256 ethStakeSigned,
        uint256 eigenStakeSigned,
        uint256 totalEthStake,
        uint256 totalEigenStake
    ) external;

    function dataStores(bytes32)
        external
        view
        returns (
            uint32 dataStoreId,
            uint32 initTime,
            uint32 storePeriodLength,
            uint32 blockNumber
        );
}
