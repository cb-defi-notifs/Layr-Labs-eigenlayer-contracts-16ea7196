// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "../interfaces/IDataLayrServiceManager.sol";

library DataStoreUtils {
    function computeDataStoreHash(
        IDataLayrServiceManager.DataStoreMetadata memory metadata
    ) 
        internal pure returns (bytes32)
    {
        bytes32 dsHash = keccak256(
            abi.encodePacked(
                metadata.headerHash,
                metadata.durationDataStoreId,
                metadata.globalDataStoreId,
                metadata.blockNumber,
                metadata.fee,
                metadata.confirmer,
                metadata.signatoryRecordHash
            )
        );
        return dsHash;
    }

    function computeDataStoreHashFromArgs(
        bytes32 headerHash,
        uint32 durationDataStoreId,
        uint32 globalDataStoreId,
        uint32 blockNumber,
        uint96 fee,
        address confirmer,
        bytes32 signatoryRecordHash
    ) internal pure returns (bytes32) {
        bytes32 dsHash = keccak256(
            abi.encodePacked(
                headerHash,
                durationDataStoreId,
                globalDataStoreId,
                blockNumber,
                fee,
                confirmer,
                signatoryRecordHash
            )
        );
        return dsHash;
    }

    function packDataStoreMetadata(
        IDataLayrServiceManager.DataStoreMetadata memory metadata
    )
        internal pure returns (bytes memory)
    {
        return (
            abi.encodePacked(
                metadata.headerHash,
                metadata.durationDataStoreId,
                metadata.globalDataStoreId,
                metadata.blockNumber,
                metadata.fee,
                metadata.confirmer,
                metadata.signatoryRecordHash
            )
        );
    }

    function packDataStoreSearchData(
        IDataLayrServiceManager.DataStoreSearchData memory searchData
    )
        internal pure returns (bytes memory)
    {
        return (
            abi.encodePacked(
                packDataStoreMetadata(searchData.metadata),
                searchData.duration,
                searchData.timestamp,
                searchData.index
            )
        );
    }

    // CONSTANTS -- commented out lines are due to inline assembly supporting *only* 'direct number constants' (for now, at least)
    // OBJECT BIT LENGTHS
    uint256 internal constant BIT_LENGTH_headerHash = 256;
    uint256 internal constant BIT_LENGTH_durationDataStoreId = 32;
    uint256 internal constant BIT_LENGTH_globalDataStoreId = 32;
    uint256 internal constant BIT_LENGTH_blockNumber = 32;
    uint256 internal constant BIT_LENGTH_fee = 96;
    uint256 internal constant BIT_LENGTH_confirmer = 160;
    uint256 internal constant BIT_LENGTH_signatoryRecordHash = 256;
    uint256 internal constant BIT_LENGTH_duration = 8;
    uint256 internal constant BIT_LENGTH_timestamp = 256;
    uint256 internal constant BIT_LENGTH_index = 32;

    // OBJECT BIT SHIFTS FOR READING FROM CALLDATA -- don't bother with using 'shr' if any of these is 0
    // uint256 internal constant BIT_SHIFT_headerHash = 256 - BIT_LENGTH_headerHash;
    // uint256 internal constant BIT_SHIFT_durationDataStoreId = 256 - BIT_LENGTH_durationDataStoreId;
    // uint256 internal constant BIT_SHIFT_globalDataStoreId = 256 - BIT_LENGTH_globalDataStoreId;
    // uint256 internal constant BIT_SHIFT_blockNumber = 256 - BIT_LENGTH_blockNumber;
    // uint256 internal constant BIT_SHIFT_fee = 256 - BIT_LENGTH_fee;
    // uint256 internal constant BIT_SHIFT_confirmer = 256 - BIT_LENGTH_confirmer;
    // uint256 internal constant BIT_SHIFT_signatoryRecordHash = 256 - BIT_LENGTH_signatoryRecordHash;
    // uint256 internal constant BIT_SHIFT_duration = 256 - BIT_LENGTH_duration;
    // uint256 internal constant BIT_SHIFT_timestamp = 256 - BIT_LENGTH_timestamp;
    // uint256 internal constant BIT_SHIFT_index = 256 - BIT_LENGTH_index;
    uint256 internal constant BIT_SHIFT_headerHash = 0;
    uint256 internal constant BIT_SHIFT_durationDataStoreId = 224;
    uint256 internal constant BIT_SHIFT_globalDataStoreId = 224;
    uint256 internal constant BIT_SHIFT_blockNumber = 224;
    uint256 internal constant BIT_SHIFT_fee = 160;
    uint256 internal constant BIT_SHIFT_confirmer = 96;
    uint256 internal constant BIT_SHIFT_signatoryRecordHash = 0;
    uint256 internal constant BIT_SHIFT_duration = 248;
    uint256 internal constant BIT_SHIFT_timestamp = 0;
    uint256 internal constant BIT_SHIFT_index = 224;

    // CALLDATA OFFSETS IN BYTES -- adding 7 and dividing by 8 here is for rounding *up* the bit amounts to bytes amounts
    // uint256 internal constant CALLDATA_OFFSET_headerHash = 0;
    // uint256 internal constant CALLDATA_OFFSET_durationDataStoreId = ((BIT_LENGTH_headerHash + 7) / 8);
    // uint256 internal constant CALLDATA_OFFSET_globalDataStoreId = CALLDATA_OFFSET_durationDataStoreId + ((BIT_LENGTH_durationDataStoreId + 7) / 8);
    // uint256 internal constant CALLDATA_OFFSET_blockNumber = CALLDATA_OFFSET_globalDataStoreId + ((BIT_LENGTH_globalDataStoreId + 7) / 8);
    // uint256 internal constant CALLDATA_OFFSET_fee = CALLDATA_OFFSET_blockNumber + ((BIT_LENGTH_blockNumber + 7) / 8);
    // uint256 internal constant CALLDATA_OFFSET_confirmer = CALLDATA_OFFSET_fee + ((BIT_LENGTH_fee + 7) / 8);
    // uint256 internal constant CALLDATA_OFFSET_signatoryRecordHash = CALLDATA_OFFSET_confirmer + ((BIT_LENGTH_confirmer + 7) / 8);
    // uint256 internal constant CALLDATA_OFFSET_duration = CALLDATA_OFFSET_signatoryRecordHash + ((BIT_LENGTH_signatoryRecordHash + 7) / 8);
    // uint256 internal constant CALLDATA_OFFSET_timestamp = CALLDATA_OFFSET_duration + ((BIT_LENGTH_duration + 7) / 8);
    // uint256 internal constant CALLDATA_OFFSET_index = CALLDATA_OFFSET_timestamp + ((BIT_LENGTH_timestamp + 7) / 8);
    uint256 internal constant CALLDATA_OFFSET_headerHash = 0;
    uint256 internal constant CALLDATA_OFFSET_durationDataStoreId = 32;
    uint256 internal constant CALLDATA_OFFSET_globalDataStoreId = 36;
    uint256 internal constant CALLDATA_OFFSET_blockNumber = 40;
    uint256 internal constant CALLDATA_OFFSET_fee = 44;
    uint256 internal constant CALLDATA_OFFSET_confirmer = 56;
    uint256 internal constant CALLDATA_OFFSET_signatoryRecordHash = 76;
    uint256 internal constant CALLDATA_OFFSET_duration = 108;
    uint256 internal constant CALLDATA_OFFSET_timestamp = 109;
    uint256 internal constant CALLDATA_OFFSET_index = 141;

    // MEMORY OFFSETS IN BYTES
    uint256 internal constant MEMORY_OFFSET_headerHash = 0;
    uint256 internal constant MEMORY_OFFSET_durationDataStoreId = 32;
    uint256 internal constant MEMORY_OFFSET_globalDataStoreId = 64;
    uint256 internal constant MEMORY_OFFSET_blockNumber = 96;
    uint256 internal constant MEMORY_OFFSET_fee = 128;
    uint256 internal constant MEMORY_OFFSET_confirmer = 160;
    uint256 internal constant MEMORY_OFFSET_signatoryRecordHash = 192;
    // I'm unsure why the memory-offsets work this way, but they do. See usage below.
    uint256 internal constant MEMORY_OFFSET_duration = 32;
    uint256 internal constant MEMORY_OFFSET_timestamp = 64;
    uint256 internal constant MEMORY_OFFSET_index = 96;

    // pointer to start of single 'bytes calldata' input -- accounts for function signture, length and offset encoding
    // uint256 internal constant pointer = 68;

    function unpackDataStoreMetadata(
        bytes calldata packedMetadata
    )
        internal pure returns (IDataLayrServiceManager.DataStoreMetadata memory metadata)
    {
        uint256 pointer;
        assembly {
            // fetch offset of `packedMetadata` input in calldata
            pointer := packedMetadata.offset
            mstore(
                // store in the headerHash memory location in `metadata`
                metadata,
                // read the headerHash from its calldata position in `packedMetadata`
                calldataload(pointer)
            )
            mstore(
                // store in the durationDataStoreId memory location in `metadata`
                add(metadata, MEMORY_OFFSET_durationDataStoreId),
                // read the durationDataStoreId from its calldata position in `packedMetadata`
                shr(BIT_SHIFT_durationDataStoreId,
                    calldataload(add(pointer, CALLDATA_OFFSET_durationDataStoreId))
                )
            )
            mstore(
                // store in the globalDataStoreId memory location in `metadata`
                add(metadata, MEMORY_OFFSET_globalDataStoreId),
                // read the globalDataStoreId from its calldata position in `packedMetadata`
                shr(BIT_SHIFT_globalDataStoreId,
                    calldataload(add(pointer, CALLDATA_OFFSET_globalDataStoreId))
                )
            )
            mstore(
                // store in the blockNumber memory location in `metadata`
                add(metadata, MEMORY_OFFSET_blockNumber),
                // read the blockNumber from its calldata position in `packedMetadata`
                shr(BIT_SHIFT_blockNumber,
                    calldataload(add(pointer, CALLDATA_OFFSET_blockNumber))
                )
            )
            mstore(
                // store in the fee memory location in `metadata`
                add(metadata, MEMORY_OFFSET_fee),
                // read the fee from its calldata position in `packedMetadata`
                shr(BIT_SHIFT_fee,
                    calldataload(add(pointer, CALLDATA_OFFSET_fee))
                )
            )
            mstore(
                // store in the confirmer memory location in `metadata`
                add(metadata, MEMORY_OFFSET_confirmer),
                // read the confirmer from its calldata position in `packedMetadata`
                shr(BIT_SHIFT_confirmer,
                    calldataload(add(pointer, CALLDATA_OFFSET_confirmer))
                )
            )
            mstore(
                // store in the signatoryRecordHash memory location in `metadata`
                add(metadata, MEMORY_OFFSET_signatoryRecordHash),
                // read the signatoryRecordHash from its calldata position in `packedMetadata`
                calldataload(add(pointer, CALLDATA_OFFSET_signatoryRecordHash))
            )
        }
        return metadata;
    }

    function unpackDataStoreSearchData(
        bytes calldata packedSearchData
    )
        internal pure returns (IDataLayrServiceManager.DataStoreSearchData memory searchData)
    {
        searchData.metadata = (unpackDataStoreMetadata(packedSearchData));
        uint256 pointer;
        assembly {
            // fetch offset of `packedSearchData` input in calldata
            pointer := packedSearchData.offset
            mstore(
                // store in the duration memory location of `searchData`
                add(searchData, MEMORY_OFFSET_duration),
                // read the duration from its calldata position in `packedSearchData`
                shr(BIT_SHIFT_duration,
                    calldataload(add(pointer, CALLDATA_OFFSET_duration))
                )
            )
            mstore(
                // store in the timestamp memory location of `searchData`
                add(searchData, MEMORY_OFFSET_timestamp),
                // read the timestamp from its calldata position in `packedSearchData`
                calldataload(add(pointer, CALLDATA_OFFSET_timestamp))
            )
            mstore(
                // store in the index memory location of `searchData`
                add(searchData, MEMORY_OFFSET_index),
                // read the index from its calldata position in `packedSearchData`
                shr(BIT_SHIFT_index,
                    calldataload(add(pointer, CALLDATA_OFFSET_index))
                )
            )
        }
        return searchData;
    }
}