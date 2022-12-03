// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IEigenPodManager.sol";
import "./IBeaconChainOracle.sol";

/**
 * @title Interface for solo staking pods that have their withdrawal credentials pointed to EigenLayer.
 * @author Layr Labs, Inc.
 */

interface IEigenPod {
    struct Validator {
        VALIDATOR_STATUS status;
        uint64 effectiveBalance; //ethpos stake in gwei
    }

    enum VALIDATOR_STATUS {
        INACTIVE, //doesnt exist
        ACTIVE, //staked on ethpos and withdrawal credentials are pointed
        OVERCOMMITTED //proven to be overcommitted to EigenLayer
    }

    // this struct keeps track of the total proven full withdrawals on behalf of an EigenPod up to and including a certain blockNumber
    struct CumulativeFullWithdrawal {
        uint32 blockNumber;
        uint64 amount;
    }

    /// @notice Used to initialize the pointers to contracts crucial to the pod's functionality, in beacon proxy construction from EigenPodManager
    function initialize(IEigenPodManager _eigenPodManager, address owner) external;

    /// @notice Called by EigenPodManager when the owner wants to create another validator.
    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable;

    /**
     * @notice Transfers ether balance of this contract to the specified recipient address
     * @notice Called by EigenPodManager to withdrawBeaconChainETH that has been added to its balance due to a withdrawal from the beacon chain.
     * @dev Called during withdrawal or slashing.
     */
    function withdrawBeaconChainETH(address recipient, uint256 amount) external;

    /// @notice The single EigenPodManager for EigenLayer
    function eigenPodManager() external view returns (IEigenPodManager);

    /// @notice The owner of this EigenPod
    function podOwner() external view returns (address);

    /**
     * @notice This function verifies that the withdrawal credentials of the podOwner are pointed to
     * this contract.  It verifies the provided proof from the validator against the beacon chain state
     * root.
     * @param pubkey is the BLS public key for the validator.
     * @param proofs is the bytes that prove the validator's metadata against a beacon state root
     * @param validatorFields are the fields of the "Validator Container", refer to consensus specs 
     * for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
     */
    function verifyCorrectWithdrawalCredentials(
        bytes calldata pubkey, 
        bytes calldata proofs, 
        bytes32[] calldata validatorFields
    ) external;
    
    /**
     * @notice This function records an overcommitment of stake to EigenLayer on behalf of a certain validator.
     *         If successful, the overcommitted are slashed (available for withdrawal whenever the pod's balance allows).
     *         They are also removed from the InvestmentManager and undelegated.
     * @param pubkey is the BLS public key for the validator.
     * @param proofs is the bytes that prove the validator's metadata against a beacon state root
     * @param validatorFields are the fields of the "Validator Container", refer to consensus specs 
     * @param beaconChainETHStrategyIndex is the index of the beaconChainETHStrategy for the pod owner for the callback to 
     *                                    the InvestmentManger in case it must be removed
     * for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
     */
    function verifyBalanceUpdate(
        bytes calldata pubkey, 
        bytes calldata proofs, 
        bytes32[] calldata validatorFields,
        uint256 beaconChainETHStrategyIndex
    ) external;
}
