// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IServiceManager.sol";
import "./IVoteWeigher.sol";
import "./IRepository.sol";
import "./IRegistry.sol";

interface IServiceFactory {
	// returns 'true' in the event that the ServiceFactory created the Repository
	function isRepository(IRepository) external view returns (bool);
	// returns 'true' in the event that the ServiceFactory created the Registry
	function isRegistry(IRegistry) external view returns (bool);
}