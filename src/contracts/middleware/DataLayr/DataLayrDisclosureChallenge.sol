// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IRepository.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IDataLayrRegistry.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../libraries/BytesLib.sol";
import "../Repository.sol";


/**
 @notice This contract is for doing interactive forced disclosure and then settling it.   
 */
contract DataLayrDisclosureChallenge {
    using BytesLib for bytes;
    IDataLayrServiceManager public dlsm;
    DisclosureChallenge public challenge;

    event DisclosureChallengeDisection(address nextInteracter);

    struct DisclosureChallenge {

        bytes32 headerHash;

        address operator;
        address challenger;

        // when commited, used for fraud proof period
        uint32 commitTime; 
        
        // false: operator's turn, true: challengers turn
        bool turn; 

        /** 
          claimed x and y coordinate of the commitment to the lower half degrees of the polynomial
          I_k(x) which interpolates the data the DataLayr operator receives
         */
        uint256 x_low; 
        uint256 y_low; 

        /**
          claimed x and y coordinate of the commitment to the higher half degrees of the polynomial
          I_k(x) which interpolates the data the DataLayr operators receives
         */
        uint256 x_high; 
        uint256 y_high; 

        // degree of the polynomial for which next phase of interactive challenge would be conducted 
        uint48 increment; 

        // degree of term in one step proof    
        uint48 oneStepDegree; 
    }


    constructor(
        bytes32 headerHash,
        address operator,
        address challenger,
        uint256 x_low,
        uint256 y_low,
        uint256 x_high,
        uint256 y_high,
        uint48 increment
    ) {
        // open disclosure challenge instant 
        challenge = DisclosureChallenge(
            headerHash,
            operator,
            challenger,
            uint32(block.timestamp),
            false,
            x_low,
            y_low,
            x_high,
            y_high,
            increment,
            0
        );

        // CRITIC: msg.sender is DataLayrDisclosureChallengeFactory; how would it react to being put inside 
        // IDataLayrServiceManager
        dlsm = IDataLayrServiceManager(msg.sender);
    }



    /** 
     @notice challenger challenges a particular half of the commitment to a polynomial P(x) of degree d. Note 
             that DisclosureChallenge already contains commitment to the degree d/2 polynomial 
             P1(x) and P2(x) given by:

             P1(s) := c_0 + c_1 * s + ... + c_{d/2} * s^(d/2)
             P2(s) := c_{d/2 + 1} * s^(d/2 + 1) ... + c_d * s^d
             P(s) := P1(s) + P2(s)

             and,
                DisclosureChallenge.(x_low, y_low) = (P1(s).x, P1(s).y)
                DisclosureChallenge.(x_high, y_high) = (P2(s).x, P2(s).y)

             The challenger then indicates which commitment, P1(s) or P2(s), it wants to challenge and also 
             supplies a partition of that commitment.  For e.g., if challenger wants to challenge P1(s), then
             challenger supplies coors1(s) and coors2(s) such that:

             coors1(s) := c_0 + c_1 * s + ... + c_{d/4} * s^(d/4) 
             coors2(s) := c_{d/4 + 1} * s^(d/2 + 1) ... + c_{d/2} * s^(d/2)
     */
    /**
     @param half indicates whether the challenge is for  P1(s) or for P2(s) 
     @param coors is of the format [coors1(s).x, coors1(s),y, coors2(s).x, coors2(s).y]                     
     */ 
    function challengeCommitmentHalf(bool half, uint256[4] memory coors)
        external
    {
        // checking that it is challenger's turn
        bool turn = challenge.turn;
        require(
            (turn && challenge.challenger == msg.sender) ||
                (!turn && challenge.operator == msg.sender),
            "Must be challenger and thier turn or operator and their turn"
        );

        // checking it is not yet time for the special one-step proof
        require(challenge.increment != 1, "Time to do one step proof");

        require(
            block.timestamp <
                challenge.commitTime + dlsm.disclosureFraudProofInterval(),
            "Fraud proof interval has passed"
        );


        /**
         @notice Check that the challenge is legitimate. For example, if the challenger wants to challenge 
                 P1(s), then it has to be the case that:

                                            P1(s) != coors1(s) + coors2(s)
         */
        uint256 x_contest;
        uint256 y_contest;
        if (half) {
            x_contest = challenge.x_low;
            y_contest = challenge.y_low;
        } else {
            x_contest = challenge.x_high;
            y_contest = challenge.y_high;
            challenge.oneStepDegree += challenge.increment;
        }

        // add the contested points and make sure they aren't what other party claimed
        uint256[2] memory sum;
        assembly {
            if iszero(call(not(0), 0x06, 0, coors, 0x80, sum, 0x40)) {
                revert(0, 0)
            }
        }
        require(
            sum[0] != x_contest || sum[1] != y_contest,
            "Cannot commit to same polynomial as DLN"
        );



        // update the records to reflect new commitment points
        challenge.x_low = coors[0];
        challenge.y_low = coors[1];
        challenge.x_high = coors[2];
        challenge.y_high = coors[3];
        challenge.turn = !turn;
        challenge.commitTime = uint32(block.timestamp);
        //half the amount to increment
        challenge.increment /= 2;

        emit DisclosureChallengeDisection(turn ? challenge.challenger : challenge.operator);
    }


    /**
     @notice This function is used for ending the forced disclosure challenge if challenger or 
             DataLayr operator didn't respond within a stipulated time.
     */
    function resolveTimeout(bytes32 headerHash) public {
        uint256 interval = dlsm.disclosureFraudProofInterval();

        // CRITIC: what is this first condition?
        require(
            block.timestamp > challenge.commitTime + interval &&
                block.timestamp < challenge.commitTime + (2 * interval),
            "Fraud proof interval has passed"
        );

        if (challenge.turn) {
            // challenger did not respond
            resolve(headerHash, false);
        } else {
            // operator did not respond
            resolve(headerHash, true);
        }
    }

    /**
     @notice This is for final-step of the interaction-style forced disclosure. Suppose DisclosureChallenge
     contains commitment for the polynomial P(x) such that:

                        P(s) := c_d * s^d + c_{d+1} * s^{d+1}.

     The final step would involve breaking commitment P(s) into two commitments:

                        P1(s) := c_d * s^d
                        P2(s) := c_{d+1} * s^{d+1}

     In this final step, the challenger or the challenged DataLayr operator has to give s^d or s^{d+1}
     depending on which half it wants to challenge.                  
     */
    function respondToDisclosureChallengeFinal(
        bool half,
        bytes32 headerHash,
        uint256 x_power,
        uint256 y_power,
        bytes calldata poly,
        bytes calldata proof
    ) external {
        bool turn = challenge.turn;
        require(
            (turn && challenge.challenger == msg.sender) ||
                (!turn && challenge.operator == msg.sender),
            "Must be challenger and their turn or operator and their turn"
        );

        // the final one-step proof 
        require(challenge.increment == 1, "Time to do dissection proof");

        require(
            block.timestamp <
                challenge.commitTime + dlsm.disclosureFraudProofInterval(),
            "Fraud proof interval has passed"
        );

        /** 
          Check that the interpolating polynomial supplied is same as what was supplied back in 
          respondToDisclosureInit in DataLayrServiceManager.sol.
         */   
        bytes32 polyHash = dlsm.getPolyHash(challenge.operator, headerHash);
        require(
            keccak256(poly) == polyHash,
            "Must provide the same polynomial coefficients as before"
        );


        /**
         Check that the monomial supplied (x_power, y_power) is same as (s^{degree}.x, s^{degree}.y)
         */
        uint48 degree = challenge.oneStepDegree;
        require(
            checkMembership(
                keccak256(abi.encodePacked(x_power, y_power)),
                degree,
                /// @dev more explanation on TauMerkleRoot in IDataLayrServiceManager.sol
                dlsm.powersOfTauMerkleRoot(),
                proof
            ),
            "Incorrect power of tau proof"
        );


        // verify that whether the forced disclosure challenge was valid
        uint256[2] memory contest_point;

        if (half) {
            // challenging lower degree term - P1(s)
            contest_point[0] = challenge.x_low;
            contest_point[1] = challenge.y_low;
        } else {
            // challenging higher degree term - P2(s)
            contest_point[0] = challenge.x_high;
            contest_point[1] = challenge.y_high;
            degree += 1;
        }

        uint256[5] memory coors;
        coors[0] = x_power;
        coors[1] = y_power;

        //this is the coefficient of the term with degree degree
        //TODO: verify that multiplying by 32 is safe from overflow
        //(Q: does this automatically make the result a uint256, or is it constrained to uint48?)
        coors[2] = poly.toUint256(degree*32);

        /** 
         Multiply the coefficient with the monomial, that is, if P1(s) is challenged then, do c_d * s^d
         */
        assembly {
            if iszero(
                call(not(0), 0x07, 0, coors, 0x60, add(coors, 0x60), 0x40)
            ) {
                revert(0, 0)
            }
        }


        if (turn) {
            // if challenger turn, challenge successful if points don't match
            resolve(
                headerHash,
                contest_point[0] != coors[3] || contest_point[1] != coors[4]
            );
        } else {
            // if operator turn, challenge successful if points match
            resolve(
                headerHash,
                contest_point[0] == coors[3] && contest_point[1] == coors[4]
            );
        }
    }

    //copied from
    function checkMembership(
        bytes32 leaf,
        uint256 index,
        bytes32 rootHash,
        bytes memory proof
    ) internal pure returns (bool) {
        require(proof.length % 32 == 0, "Invalid proof length");
        uint256 proofHeight = proof.length / 32;
        // Proof of size n means, height of the tree is n+1.
        // In a tree of height n+1, max #leafs possible is 2 ^ n
        require(index < 2**proofHeight, "Leaf index is too big");

        bytes32 proofElement;
        bytes32 computedHash = leaf;
        for (uint256 i = 32; i <= proof.length; i += 32) {
            assembly {
                proofElement := mload(add(proof, i))
            }

            if (index % 2 == 0) {
                computedHash = keccak256(
                    abi.encodePacked(computedHash, proofElement)
                );
            } else {
                computedHash = keccak256(
                    abi.encodePacked(proofElement, computedHash)
                );
            }

            index = index / 2;
        }
        return computedHash == rootHash;
    }

    function resolve(bytes32 headerHash, bool challengeSuccessful) internal {
        dlsm.resolveDisclosureChallenge(
            headerHash,
            challenge.operator,
            challengeSuccessful
        );
        selfdestruct(payable(0));
    }
}
