// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

/**
 * @title Interface for the BeaconStateOracle contract.
 * @author Layr Labs, Inc.
 */
interface IBeaconChainOracle {
    /// @notice Largest slot that has been confirmed by the oracle.
    function latestConfirmedOracleSlot() external view returns(uint64);
    /// @notice Mapping: Beacon Chain slot => the Beacon Chain state root at the specified slot.
    /// @dev This will return `bytes32(0)` if the state root is not yet finalized at the slot.
    function beaconStateRoot(uint64 slot) external view returns(bytes32);

    /// @notice Mapping: address => whether or not the address is in the set of oracle signers.
    function isOracleSigner(address _oracleSigner) external view returns(bool);

    /// @notice Mapping: Beacon Chain slot => oracle signer address => whether or not the oracle signer has voted on the state root at the slot.
    function hasVoted(uint64 slot, address oracleSigner) external view returns(bool);

    /// @notice Mapping: Beacon Chain slot => state root => total number of oracle signer votes for the state root at the slot. 
    function stateRootVotes(uint64 slot, bytes32 stateRoot) external view returns(uint256);

    /// @notice Total number of members of the set of oracle signers.
    function totalOracleSigners() external view returns(uint256);

    /// @notice Number of oracle signers that must vote for a state root in order for the state root to be finalized.
    function threshold() external view returns(uint256);

    /**
     * @notice Owner-only function used to modify the value of the `threshold` variable.
     * @param _threshold Desired new value for the `threshold` variable. Function will revert if this is set to zero.
     */
    function setThreshold(uint256 _threshold) external;

    /**
     * @notice Owner-only function used to add a signer to the set of oracle signers.
     * @param _oracleSigner Address to be added to the set.
     * @dev Function will have no effect if the `_oracleSigner`is already in the set of oracle signers.
     */
    function addOracleSigner(address _oracleSigner) external;

    /**
     * @notice Owner-only function used to remove a signer from the set of oracle signers.
     * @param _oracleSigner Address to be removed from the set.
     * @dev Function will have no effect if the `_oracleSigner`is already not in the set of oracle signers.
     */
    function removeOracleSigner(address _oracleSigner) external;

    /**
     * @notice Called by a member of the set of oracle signers to assert that the Beacon Chain state root is `stateRoot` at `slot`.
     * @dev The state root will be finalized once the total number of votes *for this exact state root at this exact slot* meets the `threshold` value.
     * @param slot The Beacon Chain slot of interest.
     * @param stateRoot The Beacon Chain state root that the caller asserts was the correct root, at the specified `slot`.
     */
    function voteForBeaconChainStateRoot(uint64 slot, bytes32 stateRoot) external;
}