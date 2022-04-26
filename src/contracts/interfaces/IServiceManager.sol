// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IRepository.sol";

// TODO: provide more functions for this spec
interface IServiceManager {
	function repository() external view returns (IRepository);
	function getServiceObjectCreationTime(bytes32 serviceObjectHash) external view returns (uint256);
	function getServiceObjectExpiry(bytes32 serviceObjectHash) external view returns (uint256);
}