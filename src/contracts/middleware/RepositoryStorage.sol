// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IRegistrationManager.sol";
import "../interfaces/IInvestmentStrategy.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IRepository.sol";
import "../utils/Timelock_Managed.sol";

/**
 * @notice This contract specifies all the state variables that are being used 
 *         within Repository contract.
 */
abstract contract RepositoryStorage is Timelock_Managed, IRepository {
    IEigenLayrDelegation public immutable delegation;
    IInvestmentManager public immutable investmentManager;
    IVoteWeigher public voteWeigher;
    IRegistrationManager public registrationManager;
    IServiceManager public serviceManager;

    constructor (IEigenLayrDelegation _delegation, IInvestmentManager _investmentManager) {
        delegation = _delegation;
        investmentManager = _investmentManager;
    }
}