// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/IRepository.sol";
import "../../interfaces/IQuorumRegistry.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IDataLayrPaymentManager.sol";
import "../Repository.sol";
import "../../libraries/DataStoreUtils.sol";
import "../../middleware/PaymentManager.sol";

import "ds-test/test.sol";

/**
 @notice This contract is used for doing interactive payment challenge
 */
contract DataLayrPaymentManager is 
    PaymentManager
     ,DSTest 
    {

    IDataLayrServiceManager public immutable dataLayrServiceManager;
    /**
     * @notice The EigenLayr delegation contract for this DataLayr which is primarily used by
     *      delegators to delegate their stake to operators who would serve as DataLayr
     *      nodes and so on.
     */

    constructor(
        IERC20 _paymentToken,
        uint256 _paymentFraudProofCollateral,
        IRepository _repository,
        IDataLayrServiceManager _dataLayrServiceManager
    )  PaymentManager(_paymentToken, _paymentFraudProofCollateral, _repository) 
    {
        dataLayrServiceManager = _dataLayrServiceManager;
    }

    //an operator can respond to challenges and breakdown the amount
    function respondToPaymentChallengeFinal(
        address operator,
        uint256 stakeIndex,
        uint48 nonSignerIndex,
        bytes32[] memory nonSignerPubkeyHashes,
        TotalStakes calldata totalStakesSigned,
        IDataLayrServiceManager.DataStoreSearchData calldata searchData
    ) external {
        // copy challenge struct to memory
        PaymentChallenge memory challenge = operatorToPaymentChallenge[operator];

        require(
            block.timestamp < challenge.settleAt,
            "DataLayrPaymentManager.respondToPaymentChallengeFinal: challenge has already passed settlement time"
        );

        //checks that searchData is valid by checking against the hash stored in DLSM's dataStoreHashesForDurationAtTimestamp
        require(
            dataLayrServiceManager.getDataStoreHashesForDurationAtTimestamp(
                searchData.duration, 
                searchData.timestamp,
                searchData.index
            ) == DataStoreUtils.computeDataStoreHash(searchData.metadata),
            "DataLayrPaymentManager.respondToPaymentChallengeFinal: search.metadata preimage is incorrect"
        );

        // recalculate the signatoryRecordHash, to verify integrity of `nonSignerPubkey` and `totalStakesSigned` inputs.
        bytes32 providedSignatoryRecordHash = keccak256(
            abi.encodePacked(
                searchData.metadata.headerHash,
                searchData.metadata.globalDataStoreId,
                nonSignerPubkeyHashes,
                totalStakesSigned.ethStakeSigned,
                totalStakesSigned.eigenStakeSigned
            )
        );
        //checking that `nonSignerPubKeyHashes` and `totalStakesSigned` are correct, now that we know that searchData is valid
        require(
            providedSignatoryRecordHash == searchData.metadata.signatoryRecordHash,
            "DataLayrPaymentManager.respondToPaymentChallengeFinal: provided nonSignerPubKeyHashes or totalStakesSigned is incorrect"
        );

        IQuorumRegistry registry = IQuorumRegistry(address(repository.registry()));

        bytes32 operatorPubkeyHash = registry.getOperatorPubkeyHash(operator);

        // calculate the true amount deserved
        uint120 trueAmount;

        //2^32 is an impossible index because it is more than the max number of registrants
        //the challenger marks 2^32 as the index to show that operator has not signed
        if (nonSignerIndex == 1 << 32) {
            for (uint256 i = 0; i < nonSignerPubkeyHashes.length; ) {
                require(
                    nonSignerPubkeyHashes[i] != operatorPubkeyHash,
                    "DataLayrPaymentManager.respondToPaymentChallengeFinal: Operator was not a signatory"
                );

                unchecked {
                    ++i;
                }
            }
            IQuorumRegistry.OperatorStake memory operatorStake = registry.getStakeFromPubkeyHashAndIndex(operatorPubkeyHash, stakeIndex);

            // scoped block helps fix stack too deep
            {
                require(
                    operatorStake.updateBlockNumber <= searchData.metadata.blockNumber,
                    "DataLayrPaymentManager.respondToPaymentChallengeFinal: Operator stake index is too late"
                );

                require(
                    operatorStake.nextUpdateBlockNumber == 0 ||
                        operatorStake.nextUpdateBlockNumber > searchData.metadata.blockNumber,
                    "DataLayrPaymentManager.respondToPaymentChallengeFinal: Operator stake index is too early"
                );
            }

            require(
                searchData.metadata.globalDataStoreId == challenge.fromTaskNumber,
                "DataLayrPaymentManager.respondToPaymentChallengeFinal: Loaded DataStoreId does not match challenged"
            );

            //TODO: assumes even eigen eth split
            trueAmount = uint120(
                (searchData.metadata.fee * operatorStake.ethStake) /
                    totalStakesSigned.ethStakeSigned /
                    2 +
                    (searchData.metadata.fee * operatorStake.eigenStake) /
                    totalStakesSigned.eigenStakeSigned /
                    2
            );
        } else {
            //either the operator must have been a non signer or the task was based off of stakes before the operator registered
            require(
                nonSignerPubkeyHashes[nonSignerIndex] == operatorPubkeyHash
                || searchData.metadata.blockNumber < registry.getFromBlockNumberForOperator(operator),
                "DataLayrPaymentManager.respondToPaymentChallengeFinal: Signer index is incorrect"
            );
        }

    {   
        //final entity is the entity calling this function, i.e., it is their turn to make the final response
        bool finalEntityCorrect = trueAmount != challenge.amount1;
        /*
        * if status is OPERATOR_TURN_ONE_STEP, it is the operator's turn. This means the challenger was the one who set challenge.amount1 last.  
        * If trueAmount != challenge.amount1, then the challenger is wrong (doesn't mean operator is right).
        */
        if (challenge.status == ChallengeStatus.OPERATOR_TURN_ONE_STEP) {
            _resolve(challenge, finalEntityCorrect ? challenge.operator : challenge.challenger);
        } 
        /*
        * if status is CHALLENGER_TURN_ONE_STEP, it is the challenger's turn. This means the operator was the one who set challenge.amount1 last.  
        * If trueAmount != challenge.amount1, then the operator is wrong and the challenger is correct
        */
        
        else if (challenge.status == ChallengeStatus.CHALLENGER_TURN_ONE_STEP) {
            _resolve(challenge, finalEntityCorrect ? challenge.challenger : challenge.operator);
        } else {
            revert("DataLayrPaymentManager.respondToPaymentChallengeFinal: Not in one step challenge phase");
        }

        challenge.status = ChallengeStatus.RESOLVED;
    }

        // update challenge struct in storage
        operatorToPaymentChallenge[operator] = challenge;
    }

}