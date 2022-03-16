// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IFeeManager.sol";
import "./IVoteWeighter.sol";

interface IQueryManager {
	function totalEigen() external view returns(uint256);
	function totalConsensusLayerEth() external returns(uint256);
	function totalEthValueOfShares() external returns(uint256);
	function createNewQuery(bytes calldata queryData) external;
    function getQueryDuration() external returns(uint256);
    function getQueryCreationTime(bytes32 queryHash) external returns(uint256);
	function getRegistrantType(address operator) external view returns(uint8);
	function numRegistrants() external view returns(uint256);
	function voteWeighter() external view returns(IVoteWeighter);
	function feeManager() external view returns(IFeeManager);
	function updateStake(address) external returns(uint256, uint256, uint256);
}