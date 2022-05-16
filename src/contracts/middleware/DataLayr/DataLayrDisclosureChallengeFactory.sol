// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./DataLayrDisclosureChallenge.sol";

/**
 * @notice Factory contract for creating new DataLayrPaymentChallenge contracts
 */
contract DataLayrDisclosureChallengeFactory {
    //creates a new 'DataLayrPaymentChallenge' contract
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
