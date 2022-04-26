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
    //called when responses are provided by operators
    IVoteWeigher public voteWeigher;
    IEigenLayrDelegation public delegation;
    IInvestmentManager public investmentManager;
    IRegistrationManager public registrationManager;
    //called when new queries are created. handles payments for queries.
    IServiceManager public serviceManager;
}