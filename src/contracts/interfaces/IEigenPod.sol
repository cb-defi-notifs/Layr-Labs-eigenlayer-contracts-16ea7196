// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IEigenPodManager.sol";
import "./IBeaconChainOracle.sol";

/**
 * @title Interface for solo staking pods that have their withdrawal credentials pointed to EigenLayer.
 * @author Layr Labs, Inc.
 */

interface IEigenPod {
    enum VALIDATOR_STATUS {
        INACTIVE, //doesnt exist
        ACTIVE, //staked on ethpos and withdrawal credentials are pointed
        OVERCOMMITTED, //proven to be overcommitted to EigenLayer
        WITHDRAWN //withdrawn from the Beacon Chain
    }

    // this struct keeps track of PartialWithdrawalClaims
    struct PartialWithdrawalClaim {
        PARTIAL_WITHDRAWAL_CLAIM_STATUS status;
        uint32 blockNumber;
        uint64 partialWithdrawalAmountGwei;
    }

    enum PARTIAL_WITHDRAWAL_CLAIM_STATUS {
        REDEEMED,
        PENDING,
        FAILED
    }

    /// @notice The length, in blocks, if the fraud proof period following a claim on the amount of partial withdrawals in an EigenPod
    function PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS() external view returns(uint32);

    /// @notice Used to initialize the pointers to contracts crucial to the pod's functionality, in beacon proxy construction from EigenPodManager
    function initialize(IEigenPodManager _eigenPodManager, address owner) external;

    /// @notice Called by EigenPodManager when the owner wants to create another validator.
    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable;

    /**
     * @notice Transfers ether balance of this contract to the specified recipient address
     * @notice Called by EigenPodManager to withdrawBeaconChainETH that has been added to its balance due to a withdrawal from the beacon chain.
     * @dev Called during withdrawal or slashing.
     */
    function withdrawRestakedBeaconChainETH(address recipient, uint256 amount) external;

    /// @notice The single EigenPodManager for EigenLayer
    function eigenPodManager() external view returns (IEigenPodManager);

    /// @notice The owner of this EigenPod
    function podOwner() external view returns (address);

    /**
     * @notice This function verifies that the withdrawal credentials of the podOwner are pointed to
     * this contract.  It verifies the provided proof from the validator against the beacon chain state
     * root.
     * @param proofs is the bytes that prove the validator's metadata against a beacon state root
     * @param validatorFields are the fields of the "Validator Container", refer to consensus specs 
     * for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
     */
    function verifyCorrectWithdrawalCredentials(
        bytes calldata proofs, 
        bytes32[] calldata validatorFields
    ) external;
    
    /**
     * @notice This function records an overcommitment of stake to EigenLayer on behalf of a certain validator.
     *         If successful, the overcommitted balance is penalized (available for withdrawal whenever the pod's balance allows).
     *         They are also removed from the InvestmentManager and undelegated.
     * @param proofs is the bytes that prove the validator's metadata against a beacon state root
     * @param validatorFields are the fields of the "Validator Container", refer to consensus specs 
     * @param beaconChainETHStrategyIndex is the index of the beaconChainETHStrategy for the pod owner for the callback to 
     *                                    the InvestmentManger in case it must be removed from the list of the podOwners strategies
     * for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
     */
    function verifyOvercommittedStake(
        bytes calldata proofs, 
        bytes32[] calldata validatorFields,
        uint256 beaconChainETHStrategyIndex
    ) external;

    /**
     * @notice This function records a full withdrawal on behalf of one of the Ethereum validators for this EigenPod
     * @param validatorIndex is the validator index for the validator.
     * @param beaconChainETHStrategyIndex is the index of the beaconChainETHStrategy for the pod owner for the callback to 
     *                                    the InvestmentManger in case it must be removed
     */
    function verifyBeaconChainFullWithdrawal(
        uint64 validatorIndex, 
        bytes calldata proofs, 
        bytes32[] calldata withdrawalFields,
        uint256 beaconChainETHStrategyIndex
    ) external;

    /**
     * @notice This function records a balance snapshot for the EigenPod. Its main functionality is to begin an optimistic
     *         claim process on the partial withdrawable balance for the EigenPod owner. The owner is claiming that they have 
     *         proven all full withdrawals until block.number, allowing their partial withdrawal balance to be easily calculated 
     *         via  
     *              address(this).balance / GWEI_TO_WEI = 
     *                  restakedExecutionLayerGwei + 
     *                  withdrawableDueToExcessGwei + 
     *                  partialWithdrawalsGwei
     *         if any other full withdrawals are proven to have happened before block.number, the partial withdrawal is marked as failed
     * @param expireBlockNumber this is the block number before a balance update must be mined to avoid race conditions with pending withdrawals
     *                          it will be set to the blockNumber at which the next full withdrawal for a validator on this pod is going to occur
     *                          or type(uint32).max otherwise
     * @dev the sender should be able to safely set the value to type(uint32).max if there are no pending full withdrawals
     */
    function recordPartialWithdrawalClaim(uint32 expireBlockNumber) external;

    /// @notice This function allows pod owners to redeem their partial withdrawals after the dispute period has passed
    function redeemPartialWithdrawals(address recipient) external;

    /**
     * @notice Withdraws `amount` gwei to the podOwner from their instantlyWithdrawableBalanceGwei
     * @param amountGwei is the amount, in gwei, to withdraw
     */
    function withdrawInstantlyWithdrawableBalanceGwei(uint64 amountGwei) external;

    /**
     * @notice Rebalances restakedExecutionLayerGwei in case penalties were previously paid from instantlyWithdrawableBalanceGwei or partial 
     *         withdrawal, so the EigenPod thinks podOwner has more restakedExecutionLayerGwei and staked balance than beaconChainETH on EigenLayer
     * @param amountGwei is the amount, in gwei, to roll over
     */
    function rollOverRollableBalance(uint64 amountGwei) external;
}