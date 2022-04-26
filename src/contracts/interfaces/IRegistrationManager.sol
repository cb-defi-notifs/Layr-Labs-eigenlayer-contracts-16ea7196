// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IRegistrationManager {
	function registerOperator(address, bytes calldata) external returns(uint8 registrantType, uint96 ethStake, uint96 eigenStake);
	function deregisterOperator(address, bytes calldata) external returns(bool);
    function totalEigenStaked() external view returns (uint96);
    function totalEthStaked() external view returns (uint96);
    function eigenStakedByOperator(address) external view returns (uint96);
    function ethStakedByOperator(address) external view returns (uint96);
    function ethAndEigenStakedForOperator(address) external view returns (uint96, uint96);
    function operatorStakes(address) external view returns (uint96, uint96);
    function totalStake() external view returns (uint96, uint96);
    function isRegistered(address operator) external view returns (bool);
}