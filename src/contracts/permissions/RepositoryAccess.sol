// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IRepository.sol";
import "../interfaces/IRepositoryAccess.sol";

abstract contract RepositoryAccess is IRepositoryAccess {
    IRepository public immutable repository;

    modifier onlyRepository() {
        require(address(repository) == msg.sender, "onlyRepository");
        _;
    }

    modifier onlyRepositoryGovernance() {
        require(
            address(repository.owner()) == msg.sender,
            "only repository governance can call this function"
        );
        _;
    }

    modifier onlyServiceManager() {
        require(msg.sender == address(repository.serviceManager()), "Only service manager can call this");
        _;
    }

    constructor(IRepository _repository) {
        repository = _repository;
    }
}