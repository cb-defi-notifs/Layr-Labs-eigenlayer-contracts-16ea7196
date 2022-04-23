// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IRepository.sol";
import "../interfaces/IEigenLayrDelegation.sol";

abstract contract VoteWeigherBaseStorage {
    IRepository public immutable repository;
    // TODO: decide if this should be immutable or upgradeable
    IEigenLayrDelegation public delegation;
    // divisor. X consensus layer ETH is treated as equivalent to (X / consensusLayerEthToEth) ETH locked into EigenLayr
    uint256 public consensusLayerEthToEth;
    constructor(IRepository _repository) {
        repository = _repository;
    }
}