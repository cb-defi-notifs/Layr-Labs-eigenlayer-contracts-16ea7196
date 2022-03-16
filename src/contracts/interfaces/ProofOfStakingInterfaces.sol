// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IProofOfStakingRegVW {
    function totalEth() external returns (uint256);
    function getEtherForOperator(address) external view returns (uint256);
}

interface IProofOfStakingServiceManager {
    function getLastFees(address) external view returns (uint256);
    function setLastFeesForOperator(address) external;
    function redeemPayment(address) external;
}

