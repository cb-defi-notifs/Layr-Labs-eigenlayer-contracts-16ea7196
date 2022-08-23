// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "../interfaces/IDataLayrServiceManager.sol";

library DataStoreHash {
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

    // OBJECT BIT LENGTHS
    uint256 internal constant BIT_LENGTH_headerHash = 256;
    uint256 internal constant BIT_LENGTH_durationDataStoreId = 32;
    uint256 internal constant BIT_LENGTH_globalDataStoreId = 32;
    uint256 internal constant BIT_LENGTH_blockNumber = 32;
    uint256 internal constant BIT_LENGTH_fee = 96;
    uint256 internal constant BIT_LENGTH_confirmer = 160;
    uint256 internal constant BIT_LENGTH_signatoryRecordHash = 256;

    // OBJECT BIT SHIFTS FOR READING FROM CALLDATA -- don't bother with using 'shr' if any of these is 0
    // uint256 internal constant BIT_SHIFT_headerHash = 256 - BIT_LENGTH_headerHash;
    // uint256 internal constant BIT_SHIFT_durationDataStoreId = 256 - BIT_LENGTH_durationDataStoreId;
    // uint256 internal constant BIT_SHIFT_globalDataStoreId = 256 - BIT_LENGTH_globalDataStoreId;
    // uint256 internal constant BIT_SHIFT_blockNumber = 256 - BIT_LENGTH_blockNumber;
    // uint256 internal constant BIT_SHIFT_fee = 256 - BIT_LENGTH_fee;
    // uint256 internal constant BIT_SHIFT_confirmer = 256 - BIT_LENGTH_confirmer;
    // uint256 internal constant BIT_SHIFT_signatoryRecordHash = 256 - BIT_LENGTH_signatoryRecordHash;
    uint256 internal constant BIT_SHIFT_headerHash = 0;
    uint256 internal constant BIT_SHIFT_durationDataStoreId = 224;
    uint256 internal constant BIT_SHIFT_globalDataStoreId = 224;
    uint256 internal constant BIT_SHIFT_blockNumber = 224;
    uint256 internal constant BIT_SHIFT_fee = 160;
    uint256 internal constant BIT_SHIFT_confirmer = 96;
    uint256 internal constant BIT_SHIFT_signatoryRecordHash = 0;

    // CALLDATA OFFSETS IN BYTES -- adding 7 and dividing by 8 here is for rounding *up* the bit amounts to bytes amounts
    // uint256 internal constant CALLDATA_OFFSET_headerHash = 0;
    // uint256 internal constant CALLDATA_OFFSET_durationDataStoreId = ((BIT_LENGTH_headerHash + 7) / 8);
    // uint256 internal constant CALLDATA_OFFSET_globalDataStoreId = CALLDATA_OFFSET_durationDataStoreId + ((BIT_LENGTH_durationDataStoreId + 7) / 8);
    // uint256 internal constant CALLDATA_OFFSET_blockNumber = CALLDATA_OFFSET_globalDataStoreId + ((BIT_LENGTH_globalDataStoreId + 7) / 8);
    // uint256 internal constant CALLDATA_OFFSET_fee = CALLDATA_OFFSET_blockNumber + ((BIT_LENGTH_blockNumber + 7) / 8);
    // uint256 internal constant CALLDATA_OFFSET_confirmer = CALLDATA_OFFSET_confirmer + ((BIT_LENGTH_confirmer + 7) / 8);
    // uint256 internal constant CALLDATA_OFFSET_signatoryRecordHash = CALLDATA_OFFSET_confirmer + ((BIT_LENGTH_confirmer + 7) / 8);
    uint256 internal constant CALLDATA_OFFSET_headerHash = 0;
    uint256 internal constant CALLDATA_OFFSET_durationDataStoreId = 32;
    uint256 internal constant CALLDATA_OFFSET_globalDataStoreId = 36;
    uint256 internal constant CALLDATA_OFFSET_blockNumber = 40;
    uint256 internal constant CALLDATA_OFFSET_fee = 44;
    uint256 internal constant CALLDATA_OFFSET_confirmer = 56;
    uint256 internal constant CALLDATA_OFFSET_signatoryRecordHash = 76;

    // MEMORY OFFSETS IN BYTES
    uint256 internal constant MEMORY_OFFSET_headerHash = 0;
    uint256 internal constant MEMORY_OFFSET_durationDataStoreId = 32;
    uint256 internal constant MEMORY_OFFSET_globalDataStoreId = 64;
    uint256 internal constant MEMORY_OFFSET_blockNumber = 96;
    uint256 internal constant MEMORY_OFFSET_fee = 128;
    uint256 internal constant MEMORY_OFFSET_confirmer = 160;
    uint256 internal constant MEMORY_OFFSET_signatoryRecordHash = 192;

    function unpackDataStoreMetadata(
        bytes calldata packedMetadata
    )
        internal pure returns (IDataLayrServiceManager.DataStoreMetadata memory metadata)
    {
        uint256 pointer;
        assembly {
            pointer := packedMetadata.offset
            mstore(
                // store in the headerHash memory location
                metadata,
                // read the headerHash from its calldata position
                calldataload(pointer)
            )
            mstore(
                // store in the durationDataStoreId memory location
                add(metadata, MEMORY_OFFSET_durationDataStoreId),
                // read the durationDataStoreId from its calldata position
                shr(BIT_SHIFT_durationDataStoreId,
                    calldataload(add(pointer, CALLDATA_OFFSET_durationDataStoreId))
                )
            )
            mstore(
                // store in the globalDataStoreId memory location
                add(metadata, MEMORY_OFFSET_globalDataStoreId),
                // read the globalDataStoreId from its calldata position
                shr(BIT_SHIFT_globalDataStoreId,
                    calldataload(add(pointer, CALLDATA_OFFSET_globalDataStoreId))
                )
            )
            mstore(
                // store in the blockNumber memory location
                add(metadata, MEMORY_OFFSET_blockNumber),
                // read the blockNumber from its calldata position
                shr(BIT_SHIFT_blockNumber,
                    calldataload(add(pointer, CALLDATA_OFFSET_blockNumber))
                )
            )
            mstore(
                // store in the fee memory location
                add(metadata, MEMORY_OFFSET_fee),
                // read the fee from its calldata position
                shr(BIT_SHIFT_fee,
                    calldataload(add(pointer, CALLDATA_OFFSET_fee))
                )
            )
            mstore(
                // store in the confirmer memory location
                add(metadata, MEMORY_OFFSET_confirmer),
                // read the confirmer from its calldata position
                shr(BIT_SHIFT_confirmer,
                    calldataload(add(pointer, CALLDATA_OFFSET_confirmer))
                )
            )
            mstore(
                // store in the signatoryRecordHash memory location
                add(metadata, MEMORY_OFFSET_signatoryRecordHash),
                // read the signatoryRecordHash from its calldata position
                calldataload(add(pointer, CALLDATA_OFFSET_signatoryRecordHash))
            )
        }
        return metadata;
    }
}
