// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IBeaconChainOracle.sol";

contract BeaconStateOracle is IBeaconChainOracle, Ownable {
    mapping(uint64 => mapping(address => bool)) public hasVoted;
    mapping(uint64 => mapping(bytes32 => uint64)) public stateRootVotes;
    mapping(uint64 => bytes32) public beaconStateRoot;
    mapping(address => bool) public isOracleSigner; 
    uint256 public threshold;

    modifier onlyOracleSigner() {
        require(isOracleSigner[msg.sender], "BeaconStateOracle.onlyOracleSigner: Not an oracle signer");
        _;
    }

    function setThreshold(uint256 _threshold) external onlyOwner {
        threshold = _threshold;
    }

    function addOracleSigner(address _oracleSigner) external onlyOwner {
        isOracleSigner[_oracleSigner] = true;
    }

    function removeOracleSigner(address _oracleSigner) external onlyOwner {
        isOracleSigner[_oracleSigner] = false;
    }

    function voteForBeaconChainStateRoot(uint64 slot, bytes32 stateRoot) external onlyOracleSigner {
        require(!hasVoted[slot][msg.sender], "BeaconStateOracle.setBeaconChainStateRoot: Signer has alreader voted");
        require(beaconStateRoot[slot] == bytes32(0), "BeaconStateOracle.setBeaconChainStateRoot: State root already finalized");
        // Mark the signer as having voted
        hasVoted[slot][msg.sender] = true;
        // Increment the vote count for the state root
        stateRootVotes[slot][stateRoot] += 1;
        // If the state root has enough votes, confirm it as the beacon state root
        if (stateRootVotes[slot][stateRoot] > threshold) {
            beaconStateRoot[slot] = stateRoot;
        }
    }

    // remove this ↓
    function getBeaconChainStateRoot() external view returns(bytes32) {
        return bytes32(0);
    }

    // remove this ↓   
    function setBeaconChainStateRoot(bytes32 beaconChainStateRoot) external {
        revert();
    }
}