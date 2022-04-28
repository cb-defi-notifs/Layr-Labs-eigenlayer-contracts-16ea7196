// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IRepository.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IInvestmentStrategy.sol";

abstract contract VoteWeigherBaseStorage {
    IRepository public immutable repository;
    IEigenLayrDelegation public immutable delegation;
    // divisor. X consensus layer ETH is treated as equivalent to (X / consensusLayerEthToEth) ETH locked into EigenLayr
    uint256 public consensusLayerEthToEth;

    IInvestmentStrategy[] public strategiesConsidered;
    constructor(IRepository _repository,IEigenLayrDelegation _delegation) {
        repository = _repository;
        delegation = _delegation;
    }
}