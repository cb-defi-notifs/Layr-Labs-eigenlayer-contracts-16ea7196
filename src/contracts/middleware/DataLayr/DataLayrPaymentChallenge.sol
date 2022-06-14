// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IRepository.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IDataLayrRegistry.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../Repository.sol";

import "ds-test/test.sol";

/**
 @notice This contract is used for doing interactive payment challenge
 */
contract DataLayrPaymentChallenge is DSTest{
    
    // DATA STRUCTURES
    struct PaymentChallenge {
        // DataLayr operator whose payment claim is being challenged,
        address operator;

        // the entity challenging with the fraudproof
        address challenger;

        // address of the DataLayr service manager contract
        address serviceManager;

        // the dump number from which payment has been computed
        uint32 fromDumpNumber;

        // the dump number until which payment has been computed to
        uint32 toDumpNumber;

        // 
        uint120 amount1;

        // 
        uint120 amount2;

        // used for recording the time when challenge was created
        uint32 commitTime; // when commited, used for fraud proof period


        // indicates the status of the challenge
        /**
         @notice The possible status are:
                    - 0: commited,
                    - 1: redeemed,
                    - 2: operator turn (dissection),
                    - 3: challenger turn (dissection),
                    - 4: operator turn (one step),
                    - 5: challenger turn (one step)
         */
        uint8 status;   
    }

    /**
     @notice  
     */
    struct SignerMetadata {
        address signer;
        uint96 ethStake;
        uint96 eigenStake;
    }


    IDataLayrServiceManager public dlsm;

    // the payment challenge 
    PaymentChallenge public challenge;



    // EVENTS
    event PaymentBreakdown(uint32 fromDumpNumber, uint32 toDumpNumber, uint120 amount1, uint120 amount2);

    
    


    constructor(
        address operator,
        address challenger,
        address serviceManager,
        uint32 fromDumpNumber,
        uint32 toDumpNumber,
        uint120 amount1,
        uint120 amount2
    ) {
        challenge = PaymentChallenge(
            operator,
            challenger,
            serviceManager,
            fromDumpNumber,
            toDumpNumber,
            amount1,
            amount2,
            // recording current timestamp as the commitTime
            uint32(block.timestamp),
            // setting DataLayr operator to respond next
            2
        );

        dlsm = IDataLayrServiceManager(serviceManager);
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
            "Must be challenger and their turn or operator and their turn"
        );


        require(
            block.timestamp <
                challenge.commitTime + dlsm.paymentFraudProofInterval(),
            "Fraud proof interval has passed"
        );


        uint32 fromDumpNumber = challenge.fromDumpNumber;
        uint32 toDumpNumber = challenge.toDumpNumber;
        uint32 diff;
        //change interval to the one challenger cares about
        // if the difference between the current start and end is even, the new interval has an endpoint halfway inbetween
        // if the difference is odd = 2n + 1, the new interval has a "from" endpoint at (start + n = end - (n + 1)) if the second half is challenged,
        //  or a "to" endpoint at (end - (2n + 2)/2 = end - (n + 1) = start + n) if the first half is challenged
        if (half) {
            diff = (toDumpNumber - fromDumpNumber) / 2;
            challenge.fromDumpNumber = fromDumpNumber + diff;
            //if next step is not final
            if (updateStatus(challenge.operator, diff)) {
                challenge.toDumpNumber = toDumpNumber;
            }
            //TODO: my understanding is that dissection=3 here, not 1 because we are challenging the second half
            updateChallengeAmounts(3, amount1, amount2);
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
            updateChallengeAmounts(1, amount1, amount2);
        }
        challenge.commitTime = uint32(block.timestamp);
        
        emit PaymentBreakdown(challenge.fromDumpNumber, challenge.toDumpNumber, challenge.amount1, challenge.amount2);
    }




    /**
     @notice This function is used for updating the status of the challenge in terms of who
             has to respond to the interactive challenge mechanism next -  is it going to be
             challenger or the DataLayr operator.   
     */
    /**
     @param operator is the DataLayr operator whose payment claim is being challenged
     @param diff is the number of DataLayr dumps across which payment is being challenged in this iteration
     */ 
    function updateStatus(address operator, uint32 diff)
        internal
        returns (bool)
    {
        // payment challenge for one data dump
        if (diff == 1) {
            //set to one step turn of either challenger or operator
            challenge.status = msg.sender == operator ? 5 : 4;
            return false;

        // payment challenge across more than one data dump
        } else {
            // set to dissection turn of either challenger or operator
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
                "Invalid amount bbbreakdown"
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
                block.timestamp < challenge.commitTime + (2 * interval),
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
        uint256 stakeIndex,
        uint48 nonSignerIndex,
        bytes32[] memory nonSignerPubkeyHashes,
        uint256 totalEthStakeSigned,
        uint256 totalEigenStakeSigned,
        bytes32 challengedDumpHeaderHash
    ) external {
        require(
            block.timestamp <
                challenge.commitTime + dlsm.paymentFraudProofInterval(),
            "Fraud proof interval has passed"
        );
        uint32 challengedDumpNumber = challenge.fromDumpNumber;
        uint8 status = challenge.status;
        address operator = challenge.operator;
        //check sigs
        require(
            dlsm.getDumpNumberSignatureHash(challengedDumpNumber) ==
                keccak256(
                    abi.encodePacked(
                        challengedDumpNumber,
                        nonSignerPubkeyHashes,
                        totalEthStakeSigned,
                        totalEigenStakeSigned
                    )
                ),
            "Sig record does not match hash"
        );

        IDataLayrRegistry dlRegistry = IDataLayrRegistry(address(IRepository(IServiceManager(address(dlsm)).repository()).registrationManager()));

        bytes32 operatorPubkeyHash = dlRegistry.getOperatorPubkeyHash(operator);

        // //calculate the true amount deserved
        uint120 trueAmount;

        //2^32 is an impossible index because it is more than the max number of registrants
        //the challenger marks 2^32 as the index to show that operator has not signed
        if (nonSignerIndex == 1 << 32) {
            for (uint256 i = 0; i < nonSignerPubkeyHashes.length; ) {
                require(nonSignerPubkeyHashes[i] != operatorPubkeyHash, "Operator was not a signatory");

                unchecked {
                    ++i;
                }
            }
            //TODO: Change this
            IDataLayrRegistry.OperatorStake memory operatorStake = dlRegistry.getStakeFromPubkeyHashAndIndex(operatorPubkeyHash, stakeIndex);

        // scoped block helps fix stack too deep
        {
            (uint32 dumpNumberFromHeaderHash, , , uint32 challengedDumpBlockNumber, ) = (dlsm.dataLayr()).dataStores(challengedDumpHeaderHash);
            require(dumpNumberFromHeaderHash == challengedDumpNumber, "specified dumpNumber does not match provided headerHash");
            require(
                operatorStake.updateBlockNumber <= challengedDumpBlockNumber,
                "Operator stake index is too late"
            );

            require(
                operatorStake.nextUpdateBlockNumber == 0 ||
                    operatorStake.nextUpdateBlockNumber > challengedDumpBlockNumber,
                "Operator stake index is too early"
            );
        }

            //TODO: Change this
            uint256 fee = dlsm.dumpNumberToFee(challengedDumpNumber);
            //TODO: assumes even eigen eth split
            trueAmount = uint120(
                (fee * operatorStake.ethStake) /
                    totalEthStakeSigned /
                    2 +
                    (fee * operatorStake.eigenStake) /
                    totalEigenStakeSigned /
                    2
            );
        } else {
            require(
                nonSignerPubkeyHashes[nonSignerIndex] == operatorPubkeyHash,
                "Signer index is incorrect"
            );
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

    function getChallengeStatus() external view returns(uint8){
        return challenge.status;
    }

    function getAmount1() external view returns (uint120){
        return challenge.amount1;
    }
    function getAmount2() external view returns (uint120){
        return challenge.amount2;
    }
    function getToDumpNumber() external view returns (uint48){
        return challenge.toDumpNumber;
    }
    function getFromDumpNumber() external view returns (uint48){
        return challenge.fromDumpNumber;
    }
    function getDiff() external view returns (uint48){
        return challenge.toDumpNumber - challenge.fromDumpNumber;
    }
}
