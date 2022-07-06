// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IRepository.sol";
import "../interfaces/IRepositoryAccess.sol";

abstract contract RepositoryAccess is IRepositoryAccess {
    // the unique, immutable Repository contract associated with this contract
    IRepository public immutable repository;

    constructor(IRepository _repository) {
        repository = _repository;
    }

    // MODIFIERS -- access controls based on stored addresses
    modifier onlyRepository() {
        require(
            msg.sender == address(repository),
            "onlyRepository"
        );
        _;
    }

    modifier onlyRepositoryGovernance() {
        require(
            msg.sender == address(repositoryGovernance()),
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

    // INTERNAL FUNCTIONS -- fetch info from repository
    function repositoryGovernance() internal view returns(address) {
        return repository.owner();
    }

    function serviceManager() internal view returns(IServiceManager) {
        return repository.serviceManager();
    }
    function registry() internal view returns(IRegistrationManager) {
        return repository.registrationManager();
    }

}