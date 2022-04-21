// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IRegistrationManager.sol";

/**
 * @notice Simple Implementation of the IRegistrationManager Interface. Handles registration and deregistration, as well as
 *          storing ETH and EIGEN stakes of registered nodes.
 */
// TODO: simple, functional implementation of the virtual functions, so this contract doesn't need to be marked as abstract
abstract contract RegistrationManagerBase is IRegistrationManager {
    /**
     * @notice struct for storing the amount of Eigen and ETH that has been staked, as well as additional data
     *          packs two uint96's into a single storage slot
     */
    struct EthAndEigenAmounts {
        uint96 ethAmount;
        uint96 eigenAmount;
    }

    // variable for storing total ETH and Eigen staked into securing the middleware
    EthAndEigenAmounts public totalStake;

    // mapping from each operator's address to its Stake for the middleware
    mapping(address => EthAndEigenAmounts) public operatorStakes;

    //TODO: do we need this variable?
    // number of registrants of this service
    uint64 public numRegistrants;

    /// @notice get total ETH staked for securing the middleware
    function totalEthStaked() public view returns (uint96) {
        return totalStake.ethAmount;
    }

    /// @notice get total Eigen staked for securing the middleware
    function totalEigenStaked() public view returns (uint96) {
        return totalStake.eigenAmount;
    }

    /// @notice get total ETH staked by delegators of the operator
    function ethStakedByOperator(address operator)
        public
        view
        returns (uint96)
    {
        return operatorStakes[operator].ethAmount;
    }

    /// @notice get total Eigen staked by delegators of the operator
    function eigenStakedByOperator(address operator)
        public
        view
        returns (uint96)
    {
        return operatorStakes[operator].eigenAmount;
    }

    /// @notice get both total ETH and Eigen staked by delegators of the operator
    function ethAndEigenStakedForOperator(address operator)
        public
        view
        returns (uint96, uint96)
    {
        EthAndEigenAmounts memory opStake = operatorStakes[operator];
        return (opStake.ethAmount, opStake.eigenAmount);
    }

    /**
     * @notice
     */
    event Registration();

    event DeregistrationCommit(
        address registrant // who started
    );

    function registerOperator(address, bytes calldata data)
        external
        virtual
        returns (uint8, uint96, uint96);

    /**
     * @notice Used by an operator to de-register itself from providing service to the middleware.
     */
// TODO: decide if address input is necessary for the standard
    function deregisterOperator(address, bytes calldata)
        external
        virtual
        returns (bool);
}