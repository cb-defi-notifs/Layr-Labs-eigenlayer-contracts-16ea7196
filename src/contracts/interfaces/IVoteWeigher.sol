// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IVoteWeigher {
	function weightOfOperatorEth(address) external returns(uint128);
	function weightOfOperatorEigen(address) external returns(uint128);
}