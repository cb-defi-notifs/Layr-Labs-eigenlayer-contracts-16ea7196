// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IRepository.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IDataLayrVoteWeigher.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../libraries/BytesLib.sol";
import "../Repository.sol";

contract DataLayrDisclosureChallenge {
    using BytesLib for bytes;
    IDataLayrServiceManager public dlsm;
    DisclosureChallenge public challenge;

    struct DisclosureChallenge {
        address operator;
        address challenger;
        uint32 commitTime; // when commited, used for fraud proof period
        bool turn; // false: operator's turn, true: challengers turn
        uint256 x_low; // claimed x and y coordinate of the commitment to the lower half degrees of the polynomial
        uint256 y_low; // interpolating the data the operator receives
        uint256 x_high; // claimed x and y coordinate of the commitment to the higher half degrees of the polynomial
        uint256 y_high; // interpolating the data the operator receives
        uint48 increment; //amount to increment degree if higher
        uint48 oneStepDegree; //degree of term in one step proof
    }

    constructor(
        address operator,
        address challenger,
        uint256 x_low,
        uint256 y_low,
        uint256 x_high,
        uint256 y_high,
        uint48 increment
    ) {
        challenge = DisclosureChallenge(
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
        dlsm = IDataLayrServiceManager(msg.sender);
    }

    //challenger challenges a particular half of the commitment
    function challengeCommitmentHalf(bool half, uint256[4] memory coors)
        external
    {
        bool turn = challenge.turn;
        require(
            (turn && challenge.challenger == msg.sender) ||
                (!turn && challenge.operator == msg.sender),
            "Must be challenger and thier turn or operator and their turn"
        );
        require(challenge.increment != 1, "Time to do one step proof");
        require(
            block.timestamp <
                challenge.commitTime + dlsm.disclosureFraudProofInterval(),
            "Fraud proof interval has passed"
        );
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
        uint256[2] memory sum;
        //add the contested points and make sure they arent what other party claimed
        assembly {
            if iszero(call(not(0), 0x06, 0, coors, 0x80, sum, 0x40)) {
                revert(0, 0)
            }
        }
        require(
            sum[0] != x_contest || sum[1] != y_contest,
            "Cannot commit to same polynomial as DLN"
        );
        //update new commitment points
        challenge.x_low = coors[0];
        challenge.y_low = coors[1];
        challenge.x_high = coors[2];
        challenge.y_high = coors[3];
        challenge.turn = !turn;
        challenge.commitTime = uint32(block.timestamp);
        //half the amount to increment
        challenge.increment /= 2;
    }

    function resolveTimeout(bytes32 headerHash) public {
        uint256 interval = dlsm.disclosureFraudProofInterval();
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

    //an operator can respond to challenges and breakdown the amount
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
            "Must be challenger and thier turn or operator and their turn"
        );
        require(challenge.increment == 1, "Time to do dissection proof");
        require(
            block.timestamp <
                challenge.commitTime + dlsm.disclosureFraudProofInterval(),
            "Fraud proof interval has passed"
        );
        bytes32 polyHash = dlsm.getPolyHash(challenge.operator, headerHash);
        require(
            keccak256(poly) == polyHash,
            "Must provide the same polynomial coefficients as before"
        );
        uint48 degree = challenge.oneStepDegree;
        //degree of proved leaf
        require(
            checkMembership(
                keccak256(abi.encodePacked(x_power, y_power)),
                degree,
                dlsm.powersOfTauMerkleRoot(),
                proof
            ),
            "Incorrect power of tau proof"
        );
        bytes32 pointRoot;
        uint256[3] memory contest_point;
        if (half) {
            //left leaf
            //challenging lower degree term
            contest_point[0] = challenge.x_low;
            contest_point[1] = challenge.y_low;
        } else {
            //right leaf
            //challenging higher degree term
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
        assembly {
            if iszero(
                call(not(0), 0x07, 0, coors, 0x60, add(coors, 0x60), 0x40)
            ) {
                revert(0, 0)
            }
        }

        if (turn) {
            //if challenger turn, challenge successful if points dont match
            resolve(
                headerHash,
                contest_point[0] != coors[3] || contest_point[1] != coors[4]
            );
        } else {
            //if operator turn, challenge successful if points match
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
