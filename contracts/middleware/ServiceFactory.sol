// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/MiddlewareInterfaces.sol";
import "../interfaces/CoreInterfaces.sol";
import "./QueryManager.sol";


contract ServiceFactory is IServiceFactory {
    mapping(IQueryManager => bool) public isQueryManager;

	constructor() {
		
	}

	function createNewQueryManager(uint256 queryDuration, IFeeManager feeManager, IVoteWeighter voteWeigher, address registrationManager) external {
		// register a new query manager
		isQueryManager[new QueryManager(queryDuration, feeManager, voteWeigher, registrationManager)] = true;
	}

	function queryManagerExists(IQueryManager queryManager) external view returns(bool) {
		return isQueryManager[queryManager];
	}
}