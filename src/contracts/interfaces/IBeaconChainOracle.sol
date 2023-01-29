// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;


interface IBeaconChainOracle {
    struct BeaconChainStateRecord {
        bytes32 root;
        uint64 votes;
    }   

    // remove these ↓
    function getBeaconChainStateRoot() external view returns(bytes32);

    function setBeaconChainStateRoot(bytes32 beaconChainStateRoot) external;

    // add these ↓

    // function beaconStateRoot(uint64 slot) external view returns(bytes32);

    // function isOracleSigner(address _oracleSigner) external view returns(bool);

    // function threshold() external view returns(uint256);

    // function setThreshold(uint256 _threshold) external;

    // function addOracleSigner(address _oracleSigner) external;

    // function removeOracleSigner(address _oracleSigner) external;

    // function voteForBeaconChainStateRoot(uint64 slot, bytes32 stateRoot) external; 

}