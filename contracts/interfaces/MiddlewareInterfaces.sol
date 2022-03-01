// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IServiceFactory {
	function createNewQueryManager(uint256 queryDuration, IFeeManager feeManager, IVoteWeighter voteWeigher, address registrationManager, address timelock) external;
	function queryManagerExists(IQueryManager queryManager) external view returns(bool);
}

interface IQueryManager {
	function createNewQuery(bytes calldata queryData) external;
    function getQueryDuration() external returns(uint256);
    function getQueryCreationTime(bytes32 queryHash) external returns(uint256);
	function getIsRegistrantActive(address operator) external view returns(bool);
	function numRegistrants() external view returns(uint256);
	function voteWeighter() external view returns(IVoteWeighter);
	function feeManager() external view returns(IFeeManager);
}

interface IFeeManager {
	function payFee(address payee) external payable;
	function onResponse(bytes32 queryHash, address operator, bytes32 reponseHash, uint256 senderWeight) external;
}

interface IVoteWeighter {
	function weightOfOperator(address) external returns(uint256);
}

interface IRegistrationManager {
	function operatorPermitted(address operator, bytes calldata data) external returns(bool);
	function operatorPermittedToLeave(address operator, bytes calldata data) external returns(bool);
}