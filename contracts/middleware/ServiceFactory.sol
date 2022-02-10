// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/MiddlewareInterfaces.sol";
import "../interfaces/CoreInterfaces.sol";
import "./QueryManager.sol";


abstract contract ServiceFactory is IServiceFactory {
    mapping(IQueryManager => bool) public isQueryManager;

	constructor(uint256 _queryDuration, IFeeManager _feeManager, IVoteWeighter _voteWeighter) {
		
	}

	function createNewQueryManager(uint256 queryDuration, IFeeManager feeManager, IVoteWeighter voteWeigher) external {
		// register a new query manager
		isQueryManager[new QueryManager(queryDuration, feeManager, voteWeigher)] = true;
	}

	function queryManagerExists(IQueryManager queryManager) external view returns(bool) {
		return isQueryManager[queryManager];
	}
}