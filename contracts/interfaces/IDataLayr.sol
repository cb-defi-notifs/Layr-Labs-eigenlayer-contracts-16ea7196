// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/**
 * @title DataLayr
 * @dev L1 contracts that handles DataLayr Node registration
 *
 */

interface IDataLayr {
    function initDataStore(
        uint256 dumpNumber,
        bytes32 ferkleRoot,
        uint32 totalBytes,
        uint32 storePeriodLength,
        address submitter,
        uint24 quorum
    ) external payable;

    function commit(
        uint256 dumpNumber,
        bytes32 ferkleRoot,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        uint8[] calldata vs
    ) external payable;
}
