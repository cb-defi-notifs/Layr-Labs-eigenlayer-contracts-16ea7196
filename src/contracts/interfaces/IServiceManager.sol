// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IRepository.sol";

// TODO: provide more functions for this spec
interface IServiceManager {
	function repository() external view returns (IRepository);
	function getTaskCreationTime(bytes32 taskHash) external view returns (uint256);
	function getTaskExpiry(bytes32 taskHash) external view returns (uint256);
}