// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


interface IBeaconChainEtherReceiver {
    function receiveBeaconChainETH() external payable; 
}