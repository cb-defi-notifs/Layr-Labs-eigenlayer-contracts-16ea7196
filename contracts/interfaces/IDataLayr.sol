// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
/**
 * @title DataLayr
 * @dev L1 contracts that handles DataLayr Node registration
 *
 */

interface IDataLayr {

    function register(string calldata socket_) external payable;

    function initDataStore(bytes32 ferkleRoot, uint32 totalBytes, uint32 storePeriodLength, address submitter, uint24 quorum) external payable;
}