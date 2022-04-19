// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IRepository.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IDataLayrVoteWeigher.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../Repository.sol";

contract DataLayrPaymentChallenge {
    IDataLayrServiceManager public dlsm;
    PaymentChallenge public challenge;

    struct PaymentChallenge {
        address operator;
        address challenger;
        uint48 fromDumpNumber;
        uint48 toDumpNumber;
        uint120 amount1;
        uint120 amount2;
        uint32 commitTime; // when commited, used for fraud proof period
        uint8 status; // 0: commited, 1: redeemed, 2: operator turn (dissection), 3: challenger turn (dissection)
        // 4: operator turn (one step), 5: challenger turn (one step)
    }

    constructor(
        address operator,
        address challenger,
        uint48 fromDumpNumber,
        uint48 toDumpNumber,
        uint120 amount1,
        uint120 amount2
    ) {
        challenge = PaymentChallenge(
            operator,
            challenger,
            fromDumpNumber,
            toDumpNumber,
            amount1,
            amount2,
            uint32(block.timestamp),
            2
        );
        dlsm = IDataLayrServiceManager(msg.sender);
    }

    //challenger challenges a particular half of the payment
    function challengePaymentHalf(
        bool half,
        uint120 amount1,
        uint120 amount2
    ) external {
        uint8 status = challenge.status;
        require(
            (status == 3 && challenge.challenger == msg.sender) ||
                (status == 2 && challenge.operator == msg.sender),
            "Must be challenger and thier turn or operator and their turn"
        );
        require(
            block.timestamp <
                challenge.commitTime + dlsm.paymentFraudProofInterval(),
            "Fraud proof interval has passed"
        );
        uint48 fromDumpNumber;
        uint48 toDumpNumber;
        if (fromDumpNumber == 0) {
            fromDumpNumber = challenge.fromDumpNumber;
            toDumpNumber = challenge.toDumpNumber;
        } else {
            fromDumpNumber = challenge.fromDumpNumber;
            toDumpNumber = challenge.toDumpNumber;
        }
        uint48 diff;
        //change interval to the one challenger cares about
        // if the difference between the current start and end is even, the new interval has an endpoint halfway inbetween
        // if the difference is odd = 2n + 1, the new interval has a "from" endpoint at (start + n = end - (n + 1)) if the second half is challenged,
        //                                                      or a "to" endpoint at (end - (2n + 2)/2 = end - (n + 1) = start + n) if the first half is challenged
        if (half) {
            diff = (toDumpNumber - fromDumpNumber) / 2;
            challenge.fromDumpNumber = fromDumpNumber + diff;
            //if next step is not final
            if (updateStatus(challenge.operator, diff)) {
                challenge.toDumpNumber = toDumpNumber;
            }
            updateChallengeAmounts(1, amount1, amount2);
        } else {
            diff = (toDumpNumber - fromDumpNumber);
            if (diff % 2 == 1) {
                diff += 1;
            }
            diff /= 2;
            //if next step is not final
            if (updateStatus(challenge.operator, diff)) {
                challenge.toDumpNumber = toDumpNumber - diff;
                challenge.fromDumpNumber = fromDumpNumber;
            }
            updateChallengeAmounts(2, amount1, amount2);
        }
        challenge.commitTime = uint32(block.timestamp);
    }

    function updateStatus(address operator, uint48 diff)
        internal
        returns (bool)
    {
        if (diff == 1) {
            //set to one step turn of either challenger or operator
            challenge.status = msg.sender == operator ? 5 : 4;
            return false;
        } else {
            //set to dissection turn of either challenger or operator
            challenge.status = msg.sender == operator ? 3 : 2;
            return true;
        }
    }

    //an operator can respond to challenges and breakdown the amount
    function updateChallengeAmounts(
        uint8 disectionType,
        uint120 amount1,
        uint120 amount2
    ) internal {
        if (disectionType == 1) {
            //if first half is challenged, break the first half of the payment into two halves
            require(
                amount1 + amount2 != challenge.amount1,
                "Invalid amount breakdown"
            );
        } else if (disectionType == 3) {
            //if second half is challenged, break the second half of the payment into two halves
            require(
                amount1 + amount2 != challenge.amount2,
                "Invalid amount breakdown"
            );
        } else {
            revert("Not in operator challenge phase");
        }
        challenge.amount1 = amount1;
        challenge.amount2 = amount2;
    }

    function resolveChallenge() public {
        uint256 interval = dlsm.paymentFraudProofInterval();
        require(
            block.timestamp > challenge.commitTime + interval &&
                block.timestamp < challenge.commitTime + 2 * interval,
            "Fraud proof interval has passed"
        );
        uint8 status = challenge.status;
        if (status == 2 || status == 4) {
            // operator did not respond
            resolve(false);
        } else if (status == 3 || status == 5) {
            // challenger did not respond
            resolve(true);
        }
    }

    //an operator can respond to challenges and breakdown the amount
    function respondToPaymentChallengeFinal(
        uint32[] calldata signatoryRecord
    ) external {
        require(
            block.timestamp <
                challenge.commitTime + dlsm.paymentFraudProofInterval(),
            "Fraud proof interval has passed"
        );
        uint48 challengedDumpNumber = challenge.fromDumpNumber;
        uint8 status = challenge.status;
        //check sigs
        require(
            dlsm.getDumpNumberSignatureHash(challengedDumpNumber) ==
                keccak256(abi.encodePacked(signatoryRecord)),
            "Sig record does not match hash"
        );
        //fetch operator id
        uint32 operatorId = IDataLayrVoteWeigher(
            address(IServiceManager(address(dlsm)).repository().voteWeigher())
        ).getOperatorId(challenge.operator);
        //an operator's bin is just the top 24 bits of their id
        uint32 operatorBin = operatorId >> 8;
        //calculate the true amount deserved
        uint120 trueAmount;
        for (uint256 i = 0; i < signatoryRecord.length; ) {
            //if this is the operators bin
            if (signatoryRecord[i] == operatorBin) {
                //if the claimsMadeInBin has a 1 bit in the operator index indicating the operator signed
                if ((1 << (operatorId % 256)) & signatoryRecord[i + 1] != 0) {
                    //divide the fee for that dump by the number of signers, which is the last element of the signatory record
                    trueAmount = uint120(
                        dlsm.getDumpNumberFee(challengedDumpNumber) /
                            signatoryRecord[signatoryRecord.length - 1]
                    );
                }
                break;
            }
            unchecked {
                i += 2;
            }
        }

        if (status == 4) {
            resolve(trueAmount != challenge.amount1);
        } else if (status == 5) {
            resolve(trueAmount == challenge.amount1);
        } else {
            revert("Not in one step challenge phase");
        }
        challenge.status = 1;
    }

    function resolve(bool challengeSuccessful) internal {
        dlsm.resolvePaymentChallenge(challenge.operator, challengeSuccessful);
        selfdestruct(payable(0));
    }
}
