// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


interface IBeaconChainWithdrawer {
    function receiveBeaconChainETH() external payable; 
}