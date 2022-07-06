// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IRepository.sol";
import "../interfaces/IRepositoryAccess.sol";

abstract contract RepositoryAccess is IRepositoryAccess {
    IRepository public immutable repository;

    constructor(IRepository _repository) {
        repository = _repository;
    }

    modifier onlyRepository() {
        require(
            msg.sender == address(repository),
            "onlyRepository"
        );
        _;
    }

    modifier onlyRepositoryGovernance() {
        require(
            msg.sender == address(repository.owner()),
            "onlyRepositoryGovernance"
        );
        _;
    }

    modifier onlyServiceManager() {
        require(
            msg.sender == address(repository.serviceManager()),
            "onlyServiceManager"
        );
        _;
    }

    modifier onlyRegistry() {
        require(
            msg.sender == address(repository.registrationManager()),
            "onlyRegistry"
        );
        _;
    }

}