// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IServiceManager.sol";
import "./IVoteWeigher.sol";
import "./IRepository.sol";

interface IServiceFactory {
	//function createNewRepository(uint256 queryDuration, IServiceManager ServiceManager, IVoteWeigher voteWeigher, address registrationManager, address timelock) external;
	function repositoryExists(IRepository) external view returns(bool);
}