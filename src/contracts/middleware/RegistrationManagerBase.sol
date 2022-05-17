// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./RegistrationManagerBaseMinusRepository.sol";

/**
 * @notice Simple Implementation of the IRegistrationManager Interface. Handles registration and deregistration, as well as
 *          storing ETH and EIGEN stakes of registered nodes.
 */
// TODO: simple, functional implementation of the virtual functions, so this contract doesn't need to be marked as abstract
contract RegistrationManagerBase is RegistrationManagerBaseMinusRepository {
    IRepository public immutable repository;
    constructor(IRepository _repository) {
        repository = _repository;
    }
    function registerOperator()
        external
        virtual
    {
        // load operator's current stakes
        EthAndEigenAmounts memory opStake = operatorStakes[msg.sender];
        require(opStake.ethAmount == 0 && opStake.eigenAmount == 0, "operator already registered");
        // get msg.sender's vote weights
        IVoteWeigher voteWeigher = repository.voteWeigher();
        opStake.ethAmount = uint96(voteWeigher.weightOfOperatorEth(msg.sender));
        opStake.eigenAmount = uint96(voteWeigher.weightOfOperatorEigen(msg.sender));
        // update total stake
        totalStake.ethAmount += opStake.ethAmount;
        totalStake.eigenAmount += opStake.eigenAmount;
        // store the operator's stake in storage
        operatorStakes[msg.sender] = opStake;
    }

    /**
     * @notice Used by an operator to de-register itself from providing service to the middleware.
     */
// TODO: decide if address input is necessary for the standard
    function deregisterOperator()
        external
        virtual
        returns (bool)
    {
// TODO: verify that the operator can deregister!
        // load operator's current stakes
        EthAndEigenAmounts memory opStake = operatorStakes[msg.sender];
        // update total stake
        totalStake.ethAmount -= opStake.ethAmount;
        totalStake.eigenAmount -= opStake.eigenAmount;
        // zero out the operator's stake in storage
        operatorStakes[msg.sender] = EthAndEigenAmounts({ethAmount:0, eigenAmount:0});
        return true;
    }
}