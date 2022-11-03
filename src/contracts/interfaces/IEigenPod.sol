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
        uint64 balance; //ethpos stake in gwei
    }

    enum VALIDATOR_STATUS {
        INACTIVE, //doesnt exist
        ACTIVE //staked on ethpos and withdrawal credentials are pointed
    }

    function podOwner() external returns(address);
    //used to initialize the pointers to contracts crucial to the pods functionality, in beacon proxy construction from EigenPodManager
    function initialize(IEigenPodManager _eigenPodManager, address owner) external;
    //called by EigenPodManager when the owner wants to create another validator
    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable;
    //called by EigenPodManager to withdrawBeaconChainETH that has been added to its balance due to a withdrawal. called during withdrawal or slashing
    function withdrawBeaconChainETH(address recipient, uint256 amount) external;
    function verifyCorrectWithdrawalCredentials(
        bytes calldata pubkey, 
        bytes calldata proofs, 
        bytes32[] calldata validatorFields
    ) external;
    function verifyBalanceUpdate(
        bytes calldata pubkey, 
        bytes calldata proofs, 
        bytes32[] calldata validatorFields
    ) external;
    function topUpPodBalance() external payable;

}
