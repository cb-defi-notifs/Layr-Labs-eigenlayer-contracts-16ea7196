// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./DataLayrDisclosureChallenge.sol";

/**
 * @notice Factory contract for creating new DataLayrPaymentChallenge contracts
 */
contract DataLayrDisclosureChallengeFactory {

    // creates a new 'DataLayrPaymentChallenge' contract
    /**
     @param headerHash is the hash of summary of the data that was asserted into DataLayr by the disperser during call to initDataStore,
     @param operator is the DataLayr operator
     @param challenger is the entity challenging the DataLayr operator
     @param x_low, @param y_low are coors1(s) in G1. For more detail see description in initInterpolatingPolynomialFraudProof
     @param x_high @param y_high are coors2(s) in G1.
     @param increment degree of coors1(x) and coors2(x)
     */
    function createDataLayrDisclosureChallenge(
        bytes32 headerHash,
        address operator,
        address challenger,
        uint256 x_low,
        uint256 y_low,
        uint256 x_high,
        uint256 y_high,
        uint48 increment
    ) external returns (address) {

        // deploy new challenge contract
        address disclosureContract = address(
            new DataLayrDisclosureChallenge(
                msg.sender,
                headerHash,
                operator,
                challenger,
                x_low,
                y_low,
                x_high,
                y_high,
                increment
            )
        );
        
        return disclosureContract;
    }
}
