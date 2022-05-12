// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IRepository.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IDataLayrRegistry.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../Repository.sol";

contract DataLayrDisclosureChallenge {
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
        bool[] calldata leftRightFlags,
        bytes32[] calldata proof
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
        //degree of proved leaf
        uint48 degree = proveDegreeLeaf(
            leftRightFlags,
            keccak256(abi.encodePacked(x_power, y_power)),
            proof
        );
        require(
            challenge.oneStepDegree == degree,
            "Correct degree was not proven"
        );
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
        //this is the coefficient of the term with degree 'degree'
        coors[2] = uint256(bytes32(poly[degree * 32:degree * 32 + 32]));
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

    function proveDegreeLeaf(
        bool[] calldata leftRightFlags,
        bytes32 nodeToProve,
        bytes32[] calldata proof
    ) public returns (uint48) {
        //prove first level of tree
        // require(dlsm.powersOfTauMerkleRoot() == keccak256(abi.encodePacked(proof[0], proof[1])), "First step of proof is not correct");
        uint256 len = leftRightFlags.length;
        // -1 because proved first level
        require(
            len == dlsm.log2NumPowersOfTau(),
            "Proof is not the correct length"
        );
        uint48 powerOf2 = 1;
        //degree of power being proved
        uint48 degree;
        bytes32 node = nodeToProve;
        for (uint i = 0; i < len; ) {
            if (leftRightFlags[i]) {
                //left branch
                node = keccak256(abi.encodePacked(node, proof[i]));
            } else {
                //right branch
                node = keccak256(abi.encodePacked(proof[i], node));
                degree += powerOf2;
                powerOf2 *= 2;
            }
            unchecked {
                ++i;
            }
        }
        require(
            node == dlsm.powersOfTauMerkleRoot(),
            "Proof doesn't match correct merkle root"
        );
        return degree;
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
