// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IRepository.sol";

// TODO: provide more functions for this spec
interface IServiceManager {
	// function payFee(address payee) external payable;
	// function onResponse(bytes32 queryHash, address operator, bytes32 reponseHash, uint256 senderWeight) external;
	function repository() external view returns (IRepository);
}