// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../contracts/libraries/DataStoreHash.sol";

import "forge-std/Test.sol";

contract DataStoreHashWrapper {
    function computeDataStoreHashExternal(
        IDataLayrServiceManager.DataStoreMetadata memory metadata
    ) 
        internal pure returns (bytes32)
    {
        return DataStoreHash.computeDataStoreHash(metadata);
    }

    function computeDataStoreHashFromArgsExternal(
        bytes32 headerHash,
        uint32 durationDataStoreId,
        uint32 globalDataStoreId,
        uint32 blockNumber,
        uint96 fee,
        address confirmer,
        bytes32 signatoryRecordHash
    ) external pure returns (bytes32) {
        return (
            DataStoreHash.computeDataStoreHashFromArgs(
                headerHash,
                durationDataStoreId,
                globalDataStoreId,
                blockNumber,
                fee,
                confirmer,
                signatoryRecordHash
            )
        );
    }

    function packDataStoreMetadataExternal(
        IDataLayrServiceManager.DataStoreMetadata memory metadata
    )
        external pure returns (bytes memory)
    {
        return DataStoreHash.packDataStoreMetadata(metadata);
    }

    function unpackDataStoreMetadataExternal(
        bytes calldata packedMetadata
    )
        external pure returns (IDataLayrServiceManager.DataStoreMetadata memory metadata)
    {
        return DataStoreHash.unpackDataStoreMetadata(packedMetadata);
    }
}

contract DataStoreHashTests is DSTest {
    DataStoreHashWrapper public dataStoreHashWrapper;

    function setUp() public {
        // deploy library wrapper contract so that we can call the library's functions that take inputs with 'calldata' location specified
        dataStoreHashWrapper = new DataStoreHashWrapper();
    }

    function testPackUnpackDataStoreMetadata(
        bytes32 headerHash,
        uint32 durationDataStoreId,
        uint32 globalDataStoreId,
        uint32 blockNumber,
        uint96 fee,
        address confirmer,
        bytes32 signatoryRecordHash
    )
        public
    {
        // form struct from arguments
        IDataLayrServiceManager.DataStoreMetadata memory metadataStructBeforePacking = 
            dataStoreMetadataFromArgs(
                headerHash,
                durationDataStoreId,
                globalDataStoreId,
                blockNumber,
                fee,
                confirmer,
                signatoryRecordHash
        );
        // pack the struct
        bytes memory packedMetadata = dataStoreHashWrapper.packDataStoreMetadataExternal(metadataStructBeforePacking);
        // unpack the struct
        IDataLayrServiceManager.DataStoreMetadata memory unpackedStruct = dataStoreHashWrapper.unpackDataStoreMetadataExternal(packedMetadata);
        // check the struct entries
        assertEq(
            headerHash, unpackedStruct.headerHash,
            "testPackUnpackDataStoreMetadata: unpacked headerHash does not match original one"
        );
        assertEq(
            durationDataStoreId, unpackedStruct.durationDataStoreId,
            "testPackUnpackDataStoreMetadata: unpacked durationDataStoreId does not match original one"
        );
        assertEq(
            globalDataStoreId, unpackedStruct.globalDataStoreId,
            "testPackUnpackDataStoreMetadata: unpacked globalDataStoreId does not match original one"
        );
        assertEq(
            blockNumber, unpackedStruct.blockNumber,
            "testPackUnpackDataStoreMetadata: unpacked blockNumber does not match original one"
        );
        assertEq(
            fee, unpackedStruct.fee,
            "testPackUnpackDataStoreMetadata: unpacked fee does not match original one"
        );
        assertEq(
            confirmer, unpackedStruct.confirmer,
            "testPackUnpackDataStoreMetadata: unpacked confirmer does not match original one"
        );
        assertEq(
            signatoryRecordHash, unpackedStruct.signatoryRecordHash,
            "testPackUnpackDataStoreMetadata: unpacked signatoryRecordHash does not match original one"
        );

        // failsafe extra check, in case we modify the struct entries and forget a specific check above -- just check the full bytes against each other
        require(
            keccak256(abi.encode(metadataStructBeforePacking)) == keccak256(abi.encode(unpackedStruct)),
            "testPackUnpackDataStoreMetadata: keccak256(abi.encode(metadataStructBeforePacking)) != keccak256(abi.encode(unpackedStruct))"
        );
    }

    function dataStoreMetadataFromArgs(
        bytes32 headerHash,
        uint32 durationDataStoreId,
        uint32 globalDataStoreId,
        uint32 blockNumber,
        uint96 fee,
        address confirmer,
        bytes32 signatoryRecordHash
    )
        internal pure returns (IDataLayrServiceManager.DataStoreMetadata memory metadataStruct)
    {
        metadataStruct = IDataLayrServiceManager.DataStoreMetadata({
            headerHash: headerHash,
            durationDataStoreId: durationDataStoreId,
            globalDataStoreId: globalDataStoreId,
            blockNumber: blockNumber,
            fee: fee,
            confirmer: confirmer,
            signatoryRecordHash: signatoryRecordHash
        });
        return metadataStruct;
    }
}
