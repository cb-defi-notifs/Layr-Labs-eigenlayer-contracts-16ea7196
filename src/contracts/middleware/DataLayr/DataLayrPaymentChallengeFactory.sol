// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./DataLayrPaymentChallenge.sol";
import "ds-test/test.sol";




/**
 * @notice This factory contract is used for creating new DataLayrPaymentChallenge contracts.
 */
contract DataLayrPaymentChallengeFactory is DSTest {

    /**
     @notice this function creates a new 'DataLayrPaymentChallenge' contract. 
     */
    /**
     @param operator is the DataLayr operator whose payment claim is being challenged,
     @param challenger is the entity challenging with the fraudproof,
     @param serviceManager is the DataLayr service manager,
     @param fromDumpNumber is the dump number from which payment has been computed,
     @param toDumpNumber is the dump number until which payment has been computed to,
     @param amount1 x
     @param amount2 y
     */
    function createDataLayrPaymentChallenge(
        address operator,
        address challenger,
        address serviceManager,
        address dlpcmAddr,
        uint32 fromDumpNumber,
        uint32 toDumpNumber,
        uint120 amount1,
        uint120 amount2
    ) external returns (address) {
        // deploy new challenge contract
        address challengeContract = address(
            new DataLayrPaymentChallenge(
                operator,
                challenger,
                serviceManager,
                dlpcmAddr,
                fromDumpNumber,
                toDumpNumber,
                amount1,
                amount2
            )
        );

        return challengeContract;
    }
}
