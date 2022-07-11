// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// import "./PaymentChallenge.sol";
// import "ds-test/test.sol";




// /**
//  * @notice This factory contract is used for creating new PaymentChallenge contracts.
//  */
// contract PaymentChallengeFactory is DSTest {

//     /**
//      @notice this function creates a new 'PaymentChallenge' contract. 
//      */
//     *
//      @param operator is the operator whose payment claim is being challenged,
//      @param challenger is the entity challenging with the fraudproof,
//      @param serviceManager is the service manager,
//      @param fromTaskNumber is the task number from which payment has been computed,
//      @param toTaskNumber is the task number until which payment has been computed to,
//      @param amount1 x
//      @param amount2 y
     
//     function createPaymentChallenge(
//         address operator,
//         address challenger,
//         address serviceManager,
//         address pcmAddr,
//         uint32 fromTaskNumber,
//         uint32 toTaskNumber,
//         uint120 amount1,
//         uint120 amount2
//     ) external returns (address) {
//         // deploy new challenge contract
//         address challengeContract = address(
//             new PaymentChallenge(
//                 operator,
//                 challenger,
//                 serviceManager,
//                 pcmAddr,
//                 fromTaskNumber,
//                 toTaskNumber,
//                 amount1,
//                 amount2
//             )
//         );

//         return challengeContract;
//     }
// }
