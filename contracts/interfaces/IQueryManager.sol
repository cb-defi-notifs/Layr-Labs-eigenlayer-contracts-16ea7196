// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IFeeManager.sol";
import "./IVoteWeighter.sol";

interface IQueryManager {
	function createNewQuery(bytes calldata queryData) external;
    function getQueryDuration() external returns(uint256);
    function getQueryCreationTime(bytes32 queryHash) external returns(uint256);
	function getIsRegistrantActive(address operator) external view returns(bool);
	function numRegistrants() external view returns(uint256);
	function voteWeighter() external view returns(IVoteWeighter);
	function feeManager() external view returns(IFeeManager);
}