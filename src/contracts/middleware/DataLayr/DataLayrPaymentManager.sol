// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/IRepository.sol";
import "../../interfaces/IQuorumRegistry.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/IDataLayrPaymentManager.sol";
import "../Repository.sol";
import "../../libraries/DataStoreHash.sol";
import "../../middleware/PaymentManager.sol";

import "ds-test/test.sol";

/**
 @notice This contract is used for doing interactive payment challenge
 */
contract DataLayrPaymentManager is 
    IDataLayrPaymentManager,
    PaymentManager
    // ,DSTest 
    {
    using SafeERC20 for IERC20;
    // DATA STRUCTURES
     /**
    @notice used for storing information on the most recent payment made to the DataLayr operator
    */
    


    enum DissectionType {
        INVALID,
        FIRST_HALF,
        SECOND_HALF
    }

    /**
     * @notice challenge window for submitting fraudproof in case of incorrect payment 
     *         claim by the registered operator 
     */
    uint256 public constant paymentFraudProofInterval = 7 days;

    /**
     * @notice the ERC20 token that will be used by the disperser to pay the service fees to
     *         DataLayr nodes.
     */
    IERC20 public immutable paymentToken;



    IDataLayrServiceManager public immutable dataLayrServiceManager;
    /**
     * @notice The EigenLayr delegation contract for this DataLayr which is primarily used by
     *      delegators to delegate their stake to operators who would serve as DataLayr
     *      nodes and so on.
     */

    /**
     @notice this is the payment that has to be made as a collateral for fraudproof 
             during payment challenges
     */
    uint256 public paymentFraudProofCollateral;




    // EVENTS
    event PaymentCommit(
        address indexed operator,
        uint32 fromDataStoreId,
        uint32 toDataStoreId,
        uint256 fee
    );
    event PaymentRedemption(address indexed operator, uint256 fee);
    event PaymentBreakdown(address indexed operator, uint32 fromDataStoreId, uint32 toDataStoreId, uint120 amount1, uint120 amount2);
    event PaymentChallengeInit(address indexed operator, address challenger);
    event PaymentChallengeResolution(address indexed operator, bool operatorWon);

    constructor(
        IERC20 _paymentToken,
        uint256 _paymentFraudProofCollateral,
        IDataLayrServiceManager _dataLayrServiceManager
    )   
        // set repository address equal to that of dataLayrServiceManager
        RepositoryAccess(_dataLayrServiceManager.repository()) 
    {
        paymentToken = _paymentToken;
        paymentFraudProofCollateral = _paymentFraudProofCollateral;
        dataLayrServiceManager = _dataLayrServiceManager;
        collateralToken = _dataLayrServiceManager.collateralToken();
        eigenLayrDelegation = _dataLayrServiceManager.eigenLayrDelegation();
    }

    

    

    function resolveChallenge(address operator) external {
        // copy challenge struct to memory
        PaymentChallenge memory challenge = operatorToPaymentChallenge[operator];

        require(
            block.timestamp > challenge.settleAt,
            "DataLayrPaymentManager.resolveChallenge: challenge has not yet reached settlement time"
        );
        ChallengeStatus status = challenge.status;
        // if operator did not respond
        if (status == ChallengeStatus.OPERATOR_TURN || status == ChallengeStatus.OPERATOR_TURN_ONE_STEP) {
            _resolve(challenge, challenge.challenger);
        // if challenger did not respond
        } else if (status == ChallengeStatus.CHALLENGER_TURN || status == ChallengeStatus.CHALLENGER_TURN_ONE_STEP) {
            _resolve(challenge, challenge.operator);
        }
    }

    //an operator can respond to challenges and breakdown the amount
    function respondToPaymentChallengeFinal(
        address operator,
        uint256 stakeIndex,
        uint48 nonSignerIndex,
        bytes32[] memory nonSignerPubkeyHashes,
        TotalStakes calldata totalStakes,
        IDataLayrServiceManager.DataStoreSearchData calldata searchData
    ) external {
        // copy challenge struct to memory
        PaymentChallenge memory challenge = operatorToPaymentChallenge[operator];

        require(
            block.timestamp < challenge.settleAt,
            "DataLayrPaymentManager.respondToPaymentChallengeFinal: challenge has already passed settlement time"
        );

        //checks that searchData is valid by checking against the hash stored in DLSM's dataStoreHashesForDurationAtTimestamp
        require(dataLayrServiceManager.getDataStoreHashesForDurationAtTimestamp(
                searchData.duration, 
                searchData.timestamp,
                searchData.index
            ) == DataStoreHash.computeDataStoreHash(searchData.metadata), "DataLayrPaymentManager.respondToPaymentChallengeFinal: search.metadata preimage is incorrect");

        //TODO: ensure that totalStakes and signedTotals from signatureChecker are the same quantity.
        bytes32 providedSigantoryRecordHash = keccak256(
            abi.encodePacked(
                searchData.metadata.headerHash,
                searchData.metadata.globalDataStoreId,
                nonSignerPubkeyHashes,
                totalStakes.ethStakeSigned,
                totalStakes.eigenStakeSigned
            )
        );
        //checking that nonSignerPubKeyHashes is correct, now that we know that searchData is valid
        require(providedSigantoryRecordHash == searchData.metadata.signatoryRecordHash, "provided nonSignerPubKeyHashes or totalStakes is incorrect");

        IQuorumRegistry registry = IQuorumRegistry(address(repository.registry()));

        bytes32 operatorPubkeyHash = registry.getOperatorPubkeyHash(operator);

        // calculate the true amount deserved
        uint120 trueAmount;

        //2^32 is an impossible index because it is more than the max number of registrants
        //the challenger marks 2^32 as the index to show that operator has not signed
        if (nonSignerIndex == 1 << 32) {
            for (uint256 i = 0; i < nonSignerPubkeyHashes.length; ) {
                require(nonSignerPubkeyHashes[i] != operatorPubkeyHash, "DataLayrPaymentManager.respondToPaymentChallengeFinal: Operator was not a signatory");

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

            require(searchData.metadata.globalDataStoreId == challenge.fromDataStoreId, "DataLayrPaymentManager.respondToPaymentChallengeFinal: Loaded DataStoreId does not match challenged");

            //TODO: assumes even eigen eth split
            trueAmount = uint120(
                (searchData.metadata.fee * operatorStake.ethStake) /
                    totalStakes.ethStakeSigned /
                    2 +
                    (searchData.metadata.fee * operatorStake.eigenStake) /
                    totalStakes.eigenStakeSigned /
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

// TODO: verify that the amounts used in this function are appropriate!
    /* 
    @notice: resolve payment challenge
    
    @param winner is the party who wins the challenge, either the challenger or the operator
    @param operatorSuccessful is true when the operator wins the challenge agains the challenger
    */
    function _resolve(PaymentChallenge memory challenge, address winner) internal {
        address operator = challenge.operator;
        address challenger = challenge.challenger;
        if (winner == operator) {
            // operator was correct, allow for another challenge
            operatorToPayment[operator].status = PaymentStatus.COMMITTED;
            operatorToPayment[operator].confirmAt = uint32(block.timestamp + paymentFraudProofInterval);
            /*
            * Since the operator hasn't been proved right (only challenger has been proved wrong)
            * transfer them only challengers collateral, not their own collateral (which is still
            * locked up in this contract)
             */
            collateralToken.safeTransfer(
                operator,
                operatorToPayment[operator].collateral
            );
            emit PaymentChallengeResolution(operator, true);
        } else {
            // challeger was correct, reset payment
            operatorToPayment[operator].status = PaymentStatus.REDEEMED;
            //give them their collateral and the operator's
            collateralToken.safeTransfer(
                challenger,
                2 * operatorToPayment[operator].collateral
            );
            emit PaymentChallengeResolution(operator, false);
        }
    }

    function getChallengeStatus(address operator) external view returns(ChallengeStatus) {
        return operatorToPaymentChallenge[operator].status;
    }

    function getAmount1(address operator) external view returns (uint120) {
        return operatorToPaymentChallenge[operator].amount1;
    }

    function getAmount2(address operator) external view returns (uint120) {
        return operatorToPaymentChallenge[operator].amount2;
    }

    function getToDataStoreId(address operator) external view returns (uint48) {
        return operatorToPaymentChallenge[operator].toDataStoreId;
    }

    function getFromDataStoreId(address operator) external view returns (uint48) {
        return operatorToPaymentChallenge[operator].fromDataStoreId;
    }

    function getDiff(address operator) external view returns (uint48) {
        return operatorToPaymentChallenge[operator].toDataStoreId - operatorToPaymentChallenge[operator].fromDataStoreId;
    }

    function getPaymentCollateral(address operator) external view returns (uint256)
    {
        return operatorToPayment[operator].collateral;
    }

    function dataStoreId() internal view returns (uint32) {
        return dataLayrServiceManager.taskNumber();
    }
}
