// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;


/*
 * @title Solidity Bytes Arrays Utils
 * @author Gonçalo Sá <goncalo.sa@consensys.net>
 *
 * @dev Bytes tightly packed arrays utility library for ethereum contracts written in Solidity.
 *      The library lets you concatenate, slice and type cast bytes arrays both in memory and storage.
 */



library DataStoreHash {

    function computeDataStoreHash(
        bytes32 headerHash, 
        uint32 dataStoreId, 
        uint32 blockNumber, 
        uint96 fee,
        bytes32 signatoryRecordHash
    ) internal pure returns(bytes32){
        //Check if provided calldata matches the hash stored in dataStoreIDsForDuration in initDataStore
        bytes32 dsHash = keccak256(
                                abi.encodePacked(
                                    headerHash,
                                    dataStoreId,
                                    blockNumber,
                                    fee,
                                    signatoryRecordHash
                                    )
                                );

        return dsHash;
    }
}