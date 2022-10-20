// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


interface IBeaconChainOracle {

    function getBeaconChainStateRoot() external view returns(bytes32);

}