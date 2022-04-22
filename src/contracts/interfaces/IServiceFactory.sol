// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IServiceManager.sol";
import "./IVoteWeigher.sol";
import "./IRepository.sol";
import "./IRegistrationManager.sol";

interface IServiceFactory {
	// returns 'true' in the event that the ServiceFactory created the Repository
	function isRepository(IRepository) external view returns (bool);
	// returns 'true' in the event that the ServiceFactory created the RegistrationManager
	function isRegistrationManager(IRegistrationManager) external view returns (bool);
}