// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IVoteWeigher {
	function weightOfOperator(address operator, uint256 quorumNumber) external returns(uint96);
	function NUMBER_OF_QUORUMS() external view returns (uint8);
}