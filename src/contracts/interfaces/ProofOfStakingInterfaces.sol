// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IProofOfStakingOracle {
    function getDepositRoot(uint256) external view returns (bytes32);
}

