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

    //used to initialize the pointers to contracts crucial to the pods functionality, in beacon proxy construction from EigenPodManager
    function initialize(IEigenPodManager _eigenPodManager, address owner) external;
    //called by EigenPodManager when the owner wants to create another validator
    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable;
    //called by EigenPodManager to withdrawETH that has been added to its balance due to a withdrawal
    //either in case of withdrawals
    function withdrawETH(address recipient, uint256 amount) external;
}
