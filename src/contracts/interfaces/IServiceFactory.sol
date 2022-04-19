// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IFeeManager.sol";
import "./IVoteWeigher.sol";
import "./IRepository.sol";

interface IServiceFactory {
	//function createNewRepository(uint256 queryDuration, IFeeManager feeManager, IVoteWeigher voteWeigher, address registrationManager, address timelock) external;
	function repositoryExists(IRepository) external view returns(bool);
}