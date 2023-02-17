// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IBeaconChainOracle.sol";

/**
 * @title Oracle contract used for bringing state roots of the Beacon Chain to the Execution Layer.
 * @author Layr Labs, Inc.
 * @notice The owner of this contract can edit a set of 'oracle signers', as well as changing the threshold number of oracle signers that must vote for a
 *  particular state root at a specified slot before the state root is considered 'confirmed'.
 */
contract BeaconChainOracle is IBeaconChainOracle, Ownable {
    /// @notice The minimum value which the `threshold` variable is allowed to take.
    uint256 public constant MINIMUM_THRESHOLD = 1;

    /// @notice Total number of members of the set of oracle signers.
    uint256 public totalOracleSigners;
    /**
     * @notice Number of oracle signers that must vote for a state root in order for the state root to be confirmed.
     * Adjustable by this contract's owner through use of the `setThreshold` function.
     * @dev We note that there is an edge case -- when the threshold is adjusted downward, if a state root already has enough votes to meet the *new* threshold,
     * the state root must still receive one additional vote from an oracle signer to be confirmed. This behavior is intended, to minimize unexpected root confirmations.
     */
    uint256 public threshold;
    /// @notice Largest slot that has been confirmed by the oracle.
    uint64 public latestConfirmedOracleSlot;

    /// @notice Mapping: Beacon Chain slot => the Beacon Chain state root at the specified slot.
    /// @dev This will return `bytes32(0)` if the state root is not yet confirmed at the slot.
    mapping(uint64 => bytes32) public beaconStateRoot;
    /// @notice Mapping: address => whether or not the address is in the set of oracle signers.
    mapping(address => bool) public isOracleSigner; 
    /// @notice Mapping: Beacon Chain slot => oracle signer address => whether or not the oracle signer has voted on the state root at the slot.
    mapping(uint64 => mapping(address => bool)) public hasVoted;
    /// @notice Mapping: Beacon Chain slot => state root => total number of oracle signer votes for the state root at the slot. 
    mapping(uint64 => mapping(bytes32 => uint256)) public stateRootVotes;

    /// @notice Emitted when the value of the `threshold` variable is changed from `previousValue` to `newValue`.
    event ThresholdModified(uint256 previousValue, uint256 newValue);

    /// @notice Emitted when the beacon chain state root at `slot` is confirmed to be `stateRoot`.
    event StateRootConfirmed(uint64 slot, bytes32 stateRoot);

    /// @notice Emitted when `addedOracleSigner` is added to the set of oracle signers.
    event OracleSignerAdded(address addedOracleSigner);

    /// @notice Emitted when `removedOracleSigner` is removed from the set of oracle signers.
    event OracleSignerRemoved(address removedOracleSigner);

    /// @notice Modifier that restricts functions to only be callable by members of the oracle signer set
    modifier onlyOracleSigner() {
        require(isOracleSigner[msg.sender], "BeaconChainOracle.onlyOracleSigner: Not an oracle signer");
        _;
    }

    constructor(address initialOwner, uint256 initialThreshold, address[] memory initialOracleSigners) {
        _transferOwnership(initialOwner);
        _setThreshold(initialThreshold);
        _addOracleSigners(initialOracleSigners);
    }

    /**
     * @notice Owner-only function used to modify the value of the `threshold` variable.
     * @param _threshold Desired new value for the `threshold` variable. Function will revert if this is set to zero.
     */
    function setThreshold(uint256 _threshold) external onlyOwner {
        _setThreshold(_threshold);
    }

    /**
     * @notice Owner-only function used to add a signer to the set of oracle signers.
     * @param _oracleSigners Array of address to be added to the set.
     * @dev Function will have no effect on the i-th input address if `_oracleSigners[i]`is already in the set of oracle signers.
     */
    function addOracleSigners(address[] memory _oracleSigners) external onlyOwner {
        _addOracleSigners(_oracleSigners);
    }

    /**
     * @notice Owner-only function used to remove a signer from the set of oracle signers.
     * @param _oracleSigners Array of address to be removed from the set.
     * @dev Function will have no effect on the i-th input address if `_oracleSigners[i]`is already not in the set of oracle signers.
     */
    function removeOracleSigners(address[] memory _oracleSigners) external onlyOwner {
        for (uint256 i = 0; i < _oracleSigners.length;) {
            if (isOracleSigner[_oracleSigners[i]]) {
                emit OracleSignerRemoved(_oracleSigners[i]);
                isOracleSigner[_oracleSigners[i]] = false;
                totalOracleSigners -= 1;
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Called by a member of the set of oracle signers to assert that the Beacon Chain state root is `stateRoot` at `slot`.
     * @dev The state root will be confirmed once the total number of votes *for this exact state root at this exact slot* meets the `threshold` value.
     * @param slot The Beacon Chain slot of interest.
     * @param stateRoot The Beacon Chain state root that the caller asserts was the correct root, at the specified `slot`.
     */
    function voteForBeaconChainStateRoot(uint64 slot, bytes32 stateRoot) external onlyOracleSigner {
        require(!hasVoted[slot][msg.sender], "BeaconChainOracle.voteForBeaconChainStateRoot: Signer has already voted");
        require(beaconStateRoot[slot] == bytes32(0), "BeaconChainOracle.voteForBeaconChainStateRoot: State root already confirmed");
        // Mark the signer as having voted
        hasVoted[slot][msg.sender] = true;
        // Increment the vote count for the state root
        stateRootVotes[slot][stateRoot] += 1;
        // If the state root has enough votes, confirm it as the beacon state root
        if (stateRootVotes[slot][stateRoot] >= threshold) {
            emit StateRootConfirmed(slot, stateRoot);
            beaconStateRoot[slot] = stateRoot;
            // update latestConfirmedOracleSlot if necessary
            if (slot > latestConfirmedOracleSlot) {
                latestConfirmedOracleSlot = slot;
            }
        }
    }

    /// @notice Internal function used for modifying the value of the `threshold` variable, used in the constructor and the `setThreshold` function
    function _setThreshold(uint256 _threshold) internal {
        require(_threshold >= MINIMUM_THRESHOLD, "BeaconChainOracle._setThreshold: cannot set threshold below MINIMUM_THRESHOLD");
        emit ThresholdModified(threshold, _threshold);
        threshold = _threshold;
    }

    /// @notice Internal counterpart of the `addOracleSigners` function. Also used in the constructor.
    function _addOracleSigners(address[] memory _oracleSigners) internal {
        for (uint256 i = 0; i < _oracleSigners.length;) {
            if (!isOracleSigner[_oracleSigners[i]]) {
                emit OracleSignerAdded(_oracleSigners[i]);
                isOracleSigner[_oracleSigners[i]] = true;
                totalOracleSigners += 1;
            }
            unchecked {
                ++i;
            }
        }
    }
}