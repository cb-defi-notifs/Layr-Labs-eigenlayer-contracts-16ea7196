// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IServiceFactory {
	function createNewQueryManager(uint256 queryDuration, IFeeManager feeManager, IVoteWeighter voteWeigher) external;
	function queryManagerExists(IQueryManager queryManager) external view returns(bool);
}

interface IQueryManager {
	function createNewQuery(bytes calldata queryData) external;
    function getQueryDuration() external returns(uint256);
    function getQueryCreationTime(bytes32 queryHash) external returns(uint256);
}

interface IFeeManager {
	function payFee(address payee) external;
	function onResponse(bytes32 queryHash, address operator, bytes32 reponseHash, uint256 senderWeight) external;
	function voteWeighter() external view returns(IVoteWeighter);
}

interface IVoteWeighter {
	function weightOfDelegate(address) external returns(uint256);
	function weightOfDelegator(address) external returns(uint256);
}