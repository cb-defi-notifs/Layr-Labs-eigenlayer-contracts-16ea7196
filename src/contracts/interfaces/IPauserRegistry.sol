// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/**
 * @title Interface for the `PauserRegistry` contract.
 * @author Layr Labs, Inc.
 */
interface IPauserRegistry {
    function pauser() external view returns (address);
    function unpauser() external view returns (address);
}
