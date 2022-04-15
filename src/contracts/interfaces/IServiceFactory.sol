// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IFeeManager.sol";
import "./IVoteWeigher.sol";
import "./IQueryManager.sol";

interface IServiceFactory {
	//function createNewQueryManager(uint256 queryDuration, IFeeManager feeManager, IVoteWeigher voteWeigher, address registrationManager, address timelock) external;
	function queryManagerExists(IQueryManager) external view returns(bool);
}