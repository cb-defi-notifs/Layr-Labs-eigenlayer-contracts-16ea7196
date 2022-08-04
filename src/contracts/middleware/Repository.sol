// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IRegistry.sol";
import "../interfaces/IRepository.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

contract Repository is Ownable, Initializable, IRepository {
    IEigenLayrDelegation public immutable delegation;
    IInvestmentManager public immutable investmentManager;
    IVoteWeigher public voteWeigher;
    IRegistry public registry;
    IServiceManager public serviceManager;

    constructor (IEigenLayrDelegation _delegation, IInvestmentManager _investmentManager) {
        delegation = _delegation;
        investmentManager = _investmentManager;
    }

    /// @notice returns the owner of the repository contract
    function owner() public view override(Ownable, IRepository) returns (address) {
        return Ownable.owner();
    }

    /**
     @notice used for setting the associated contracts for the middleware.
     */
    function initialize(
        IVoteWeigher _voteWeigher,
        IServiceManager _serviceManager,
        IRegistry _registry,
        address initialOwner
    ) external initializer {
        voteWeigher = _voteWeigher;
        serviceManager = _serviceManager;
        registry = _registry;
        _transferOwnership(initialOwner);
    }

    /// @notice sets the service manager for the middleware's repository
    function setServiceManager(IServiceManager _serviceManager) external onlyOwner {
        serviceManager = _serviceManager;
    }

    /// @notice sets the Registry for the middleware's repository
    function setRegistry(IRegistry _registry) external onlyOwner {
        registry = _registry;
    }

    /// @notice sets the vote weigher for the middleware's repository
    function setVoteWeigher(IVoteWeigher _voteWeigher) external onlyOwner {
        voteWeigher = _voteWeigher;
    }
}
