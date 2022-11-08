// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/**
 * @title Interface for a middleware / service that may look at past stake amounts.
 * @author Layr Labs, Inc.
 * @notice Specifically, this interface is designed for services that consult stake amounts up to `BLOCK_STALE_MEASURE`
 * blocks in the past. This may be necessary due to, e.g., network processing & communication delays, or to avoid race conditions
 * that could be present with coordinating aggregate operator signatures while service operators are registering & de-registering.
 */
interface IDelayedService {
    /// @notice The maximum amount of blocks in the past that the service will consider stake amounts to still be 'valid'.
    function BLOCK_STALE_MEASURE() external view returns(uint32);    
}
