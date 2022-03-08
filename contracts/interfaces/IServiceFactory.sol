// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IFeeManager.sol";
import "./IVoteWeighter.sol";
import "./IQueryManager.sol";

interface IServiceFactory {
	function createNewQueryManager(uint256 queryDuration, IFeeManager feeManager, IVoteWeighter voteWeigher, address registrationManager, address timelock) external;
	function queryManagerExists(IQueryManager queryManager) external view returns(bool);
}