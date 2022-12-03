// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IInvestmentManager.sol";
import "./IEigenPod.sol";
import "./IBeaconChainOracle.sol";

/**
 * @title Interface for factory that creates and manages solo staking pods that have their withdrawal credentials pointed to EigenLayer.
 * @author Layr Labs, Inc.
 */

interface IEigenPodManager {
    /**
     * @notice Creates an EigenPod for the sender.
     * @dev Function will revert if the `msg.sender` already has an EigenPod.
     */
    function createPod() external;

    /**
     * @notice Stakes for a new beacon chain validator on the sender's EigenPod. 
     * Also creates an EigenPod for the sender if they don't have one already.
     * @param pubkey The 48 bytes public key of the beacon chain validator.
     * @param signature The validator's signature of the deposit data.
     * @param depositDataRoot The root/hash of the deposit data for the validator's deposit.
     */
    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable;
    
    /**
     * @notice Withdraws ETH that has been withdrawn from the beacon chain from the EigenPod.
     * @param podOwner The owner of the pod whose balance must be withdrawn.
     * @param recipient The recipient of withdrawn ETH.
     * @param amount The amount of ETH to withdraw.
     * @dev Callable only by the InvestmentManager contract.
     */
    function withdrawBeaconChainETH(address podOwner, address recipient, uint256 amount) external;

    /**
     * @notice Sends ETH from the EigenPod to the EigenPodManager in order to fullfill its obligations to EigenLayer
     * @param podOwner The owner of the pod whose balance is being sent.
     * @dev Callable only by the podOwner's pod.
     */
    function addSlashedBalance(address podOwner) external payable;

    /**
     * @notice Updates the oracle contract that provides the beacon chain state root
     * @param newBeaconChainOracle is the new oracle contract being pointed to
     * @dev Callable only by the owner of the InvestmentManager (i.e. governance).
     */
    function updateBeaconChainOracle(IBeaconChainOracle newBeaconChainOracle) external;

    /// @notice Returns the address of the `podOwner`'s EigenPod (whether it is deployed yet or not).
    function getPod(address podOwner) external view returns(IEigenPod);

    /// @notice Oracle contract that provides updates to the beacon chain's state
    function beaconChainOracle() external view returns(IBeaconChainOracle);    

    /// @notice Returns the latest beacon chain state root posted to the beaconChainOracle.
    function getBeaconChainStateRoot() external view returns(bytes32);

    /// @notice EigenLayer's InvestmentManager contract
    function investmentManager() external view returns(IInvestmentManager);

    function hasPod(address podOwner) external view returns (bool);
}
