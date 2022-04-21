// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IRepository.sol";
import "../interfaces/IEigenLayrDelegation.sol";

abstract contract VoteWeigherBaseStorage {
    // TODO: decide if this should be immutable or upgradeable
    IEigenLayrDelegation public delegation;
    // not set in constructor, since the repository sets the address of the vote weigher in
    // its own constructor, and therefore the vote weigher must be deployed first
    IRepository public repository;
    // divisor. X consensus layer ETH is treated as equivalent to (X / consensusLayerEthToEth) ETH locked into EigenLayr
    uint256 public consensusLayerEthToEth;
}