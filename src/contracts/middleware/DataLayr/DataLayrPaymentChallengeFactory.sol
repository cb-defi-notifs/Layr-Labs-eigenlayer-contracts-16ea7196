// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./DataLayrPaymentChallenge.sol";

/**
 * @notice Factory contract for creating new DataLayrPaymentChallenge contracts
 */
contract DataLayrPaymentChallengeFactory {
    //creates a new 'DataLayrPaymentChallenge' contract
    function createDataLayrPaymentChallenge(
        address operator,
        address challenger,
        uint48 fromDumpNumber,
        uint48 toDumpNumber,
        uint120 amount1,
        uint120 amount2
    ) external returns (address) {
        // deploy new challenge contract
        address challengeContract = address(
            new DataLayrPaymentChallenge(
                operator,
                challenger,
                fromDumpNumber,
                toDumpNumber,
                amount1,
                amount2
            )
        );
        return challengeContract;
    }
}
