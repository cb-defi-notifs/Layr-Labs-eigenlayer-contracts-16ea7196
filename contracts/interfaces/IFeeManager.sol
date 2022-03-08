// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IFeeManager {
	function payFee(address payee) external payable;
	function onResponse(bytes32 queryHash, address operator, bytes32 reponseHash, uint256 senderWeight) external;
}