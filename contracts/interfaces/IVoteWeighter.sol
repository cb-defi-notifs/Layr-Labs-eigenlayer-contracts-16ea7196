// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IVoteWeighter {
	function weightOfOperatorEth(address) external returns(uint256);
	function weightOfOperatorEigen(address) external returns(uint256);
}