// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IQuorumRegistry.sol";

interface IECDSARegistry is IQuorumRegistry {
    function getCorrectStakeHash(uint256 index, uint32 blockNumber) external returns (bytes32);
}
