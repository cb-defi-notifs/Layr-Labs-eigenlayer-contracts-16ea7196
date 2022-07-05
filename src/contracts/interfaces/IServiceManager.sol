// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IRepositoryAccess.sol";

// TODO: provide more functions for this spec
interface IServiceManager is IRepositoryAccess {
	function getTaskCreationTime(bytes32 taskHash) external view returns (uint256);
	function getTaskExpiry(bytes32 taskHash) external view returns (uint256);
}