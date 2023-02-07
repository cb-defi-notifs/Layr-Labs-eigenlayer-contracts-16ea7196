// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "../../contracts/interfaces/IBeaconChainOracle.sol";



contract BeaconChainOracleMock is IBeaconChainOracle {

    bytes32 public mockBeaconChainStateRoot;

    function getBeaconChainStateRoot() external view returns(bytes32){
        return mockBeaconChainStateRoot;
    }

    function setBeaconChainStateRoot(bytes32 beaconChainStateRoot) external {
        mockBeaconChainStateRoot = beaconChainStateRoot;
    }

    function beaconStateRoot(uint64 /*slot*/) external view returns(bytes32) {
        return mockBeaconChainStateRoot;
    }

    function isOracleSigner(address /*_oracleSigner*/) external pure returns(bool) {
        return true;
    }

    function hasVoted(uint64 /*slot*/, address /*oracleSigner*/) external pure returns(bool) {
        return true;
    }

    function stateRootVotes(uint64 /*slot*/, bytes32 /*stateRoot*/) external pure returns(uint256) {
        return 0;
    }

    function totalOracleSigners() external pure returns(uint256) {
        return 0;
    }

    function threshold() external pure returns(uint256) {
        return 0;
    }

    function setThreshold(uint256 /*_threshold*/) external pure {}

    function addOracleSigner(address /*_oracleSigner*/) external pure {}

    function removeOracleSigner(address /*_oracleSigner*/) external pure {}

    function voteForBeaconChainStateRoot(uint64 /*slot*/, bytes32 /*stateRoot*/) external pure {}
}
