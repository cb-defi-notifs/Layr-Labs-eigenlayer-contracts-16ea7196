// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IRegistrationManager {
	function operatorPermitted(address, bytes calldata) external returns(bool);
	function operatorPermittedToLeave(address, bytes calldata) external returns(bool);
}