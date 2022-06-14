// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IRegistrationManager.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "./RepositoryStorage.sol";

/**
 * @notice This is the contract for managing queries in any middleware. Each middleware has a
 *         a repository. The main functionalities of this contract are:
 *             - Enable mechanism for an operator to register with the middleware so that it can
 *               respond to the middleware's queries,
 *             - Enable mechanism for an operator to de-register with the middleware,
 *             - Enable mechanism for updating the stake that is being deployed by an
 *               operator for validating the queries of the middleware,
 *             - Enable mechanism for creating new queries by the middleware, responding to
 *               existing queries by operators and finalize the outcome of the queries.
 */
contract Repository is Initializable, RepositoryStorage {

    constructor (IEigenLayrDelegation _delegation, IInvestmentManager _investmentManager)
    RepositoryStorage(_delegation, _investmentManager) {
    }

    function initialize(
        IVoteWeigher _voteWeigher,
        IServiceManager _serviceManager,
        IRegistrationManager _registrationManager,
        address initialOwner
    ) external initializer {
        voteWeigher = _voteWeigher;
        serviceManager = _serviceManager;
        registrationManager = _registrationManager;
        _transferOwnership(initialOwner);
    }

    /// @notice sets the service manager for the middleware's repository
    function setServiceManager(IServiceManager _serviceManager) external onlyOwner {
        serviceManager = _serviceManager;
    }

    /// @notice sets the registration manager for the middleware's repository
    function setRegistrationManager(IRegistrationManager _registrationManager) external onlyOwner {
        registrationManager = _registrationManager;
    }

    /// @notice sets the vote weigher for the middleware's repository
    function setVoteWeigher(IVoteWeigher _voteWeigher) external onlyOwner {
        voteWeigher = _voteWeigher;
    }
}
