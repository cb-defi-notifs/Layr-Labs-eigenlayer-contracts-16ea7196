// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IRegistrationManager {
	function registerOperator(address, bytes calldata) external returns(uint8 registrantType, uint96 ethStake, uint96 eigenStake);
	function deregisterOperator(address, bytes calldata) external returns(bool);
}