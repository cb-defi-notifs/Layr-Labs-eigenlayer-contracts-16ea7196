// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;


interface IBeaconChainOracle {

    function getBeaconChainStateRoot() external view returns(bytes32);
    function setBeaconChainStateRoot(bytes32 beaconChainStateRoot) external;

}