// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "../interfaces/IDataLayrServiceManager.sol";

library DataStoreHash {
    function computeDataStoreHash(
        IDataLayrServiceManager.DataStoreMetadata memory metadata
    ) internal pure returns (bytes32) {
        //Check if provided calldata matches the hash stored in dataStoreIDsForDuration in initDataStore
        bytes32 dsHash = keccak256(
            abi.encodePacked(
                metadata.headerHash,
                metadata.globalDataStoreId,
                metadata.durationDataStoreId,
                metadata.blockNumber,
                metadata.fee,
                metadata.signatoryRecordHash
            )
        );

        return dsHash;
    }

    function computeDataStoreHashFromArgs(
        bytes32 headerHash,
        uint32 globalDataStoreId,
        uint32 durationDataStoreId,
        uint32 blockNumber,
        uint96 fee,
        bytes32 signatoryRecordHash
    ) internal pure returns (bytes32) {
        //Check if provided calldata matches the hash stored in dataStoreIDsForDuration in initDataStore

        bytes32 dsHash = keccak256(
            abi.encodePacked(
                headerHash,
                globalDataStoreId,
                durationDataStoreId,
                blockNumber,
                fee,
                signatoryRecordHash
            )
        );

        return dsHash;
    }
}
