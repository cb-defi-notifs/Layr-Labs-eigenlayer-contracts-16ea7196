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
import "../../permissions/RepositoryAccess.sol";
import "../../libraries/DataStoreHash.sol";

import "ds-test/test.sol";

/**
 @notice This contract is used for doing interactive payment challenge
 */
contract DataLayrPaymentManager is 
    RepositoryAccess, 
    IDataLayrPaymentManager
    // ,DSTest 
    {
    using SafeERC20 for IERC20;
    // DATA STRUCTURES
     /**
    @notice used for storing information on the most recent payment made to the DataLayr operator
    */
    struct Payment {
        // dataStoreId starting from which payment is being claimed 
        uint32 fromDataStoreId; 
        // dataStoreId until which payment is being claimed (exclusive) 
        uint32 toDataStoreId; 
        // recording when the payment will optimistically be confirmed; used for fraud proof period
        uint32 confirmAt; 
        // payment for range [fromDataStoreId, toDataStoreId)
        /// @dev max 1.3e36, keep in mind for token decimals
        uint120 amount;
        // indicates the status of the payment
        /**
         @notice The possible statuses are:
                    - 0: REDEEMED,
                    - 1: COMMITTED,
                    - 2: CHALLENGED
         */
        PaymentStatus status; 
        //amount of collateral placed on this payment. stored in case `paymentFraudProofCollateral` changes
        uint256 collateral;
    }

    struct PaymentChallenge {
        // DataLayr operator whose payment claim is being challenged
        address operator;
        // the entity challenging with the fraudproof
        address challenger;
        // address of the DataLayr service manager contract
        address serviceManager;
        // the DataStoreId from which payment has been claimed
        uint32 fromDataStoreId;
        // the DataStoreId until which payment has been claimed
        uint32 toDataStoreId;
        // bisection amounts -- interactive fraudproof involves repeated bisection claims
        uint120 amount1;
        uint120 amount2;
        // used for recording the time when challenge will be settled, used for fraud proof period
        uint32 settleAt;
        // indicates the status of the challenge
        /**
         @notice The possible statuses are:
                    - 0: RESOLVED,
                    - 1: operator turn (dissection),
                    - 2: challenger turn (dissection),
                    - 3: operator turn (one step),
                    - 4: challenger turn (one step)
         */
        ChallengeStatus status;   
    }

    struct TotalStakes {
        uint256 ethStakeSigned;
        uint256 eigenStakeSigned;
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

    // collateral token used for placing collateral on challenges & payment commits
    IERC20 public immutable collateralToken;

    IDataLayrServiceManager public immutable dataLayrServiceManager;
    /**
     * @notice The EigenLayr delegation contract for this DataLayr which is primarily used by
     *      delegators to delegate their stake to operators who would serve as DataLayr
     *      nodes and so on.
     */
    /**
      @dev For more details, see EigenLayrDelegation.sol. 
     */
    IEigenLayrDelegation public immutable eigenLayrDelegation;

    /**
     @notice this is the payment that has to be made as a collateral for fraudproof 
             during payment challenges
     */
    uint256 public paymentFraudProofCollateral;

    /*
        * @notice mapping between the operator and its current committed payment
        *  or last redeemed payment 
    */
    mapping(address => Payment) public operatorToPayment;
    // operator => PaymentChallenge
    mapping(address => PaymentChallenge) public operatorToPaymentChallenge;
    // deposits of future fees to be drawn against when paying for DataStores
    mapping(address => uint256) public depositsOf;
    // depositors => addresses approved to spend deposits => allowance
    mapping(address => mapping(address => uint256)) public allowances;

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

    function depositFutureFees(address onBehalfOf, uint256 amount) external {
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);
        depositsOf[onBehalfOf] += amount;
    }

    function setPermanentAllowance(address allowed, uint256 amount) public {
        allowances[msg.sender][allowed] = amount;
    }

    function payFee(address initiator, address payer, uint256 feeAmount) external onlyServiceManager {
        //todo: can this be a permanent allowance? decreases an sstore per fee paying.
        if(initiator != payer){
            require(allowances[payer][initiator] >= feeAmount, "initiator not allowed to spend payers balance");
            if(allowances[payer][initiator] != type(uint256).max) {
                allowances[payer][initiator] -= feeAmount;
            }
        }
        depositsOf[payer] -= feeAmount;
    }

    function setPaymentFraudProofCollateral(
        uint256 _paymentFraudProofCollateral
    ) public onlyRepositoryGovernance {
        paymentFraudProofCollateral = _paymentFraudProofCollateral;
    }

    /**
     @notice This is used by a DataLayr operator to make claim on the @param amount that they deserve 
             for their service since their last payment until @param toDataStoreId  
     **/
    function commitPayment(uint32 toDataStoreId, uint120 amount) external {
        IQuorumRegistry registry = IQuorumRegistry(address(repository.registry()));

        // only registered DataLayr operators can call
        require(
            registry.getOperatorType(msg.sender) != 0,
            "Only registered operators can call this function"
        );

        require(toDataStoreId <= dataStoreId(), "Cannot claim future payments");

        // can only claim for a payment after redeeming the last payment
        require(
            operatorToPayment[msg.sender].status == PaymentStatus.REDEEMED,
            "Require last payment is redeemed"
        );

        // operator puts up collateral which can be slashed in case of wrongful payment claim
        collateralToken.safeTransferFrom(
            msg.sender,
            address(this),
            paymentFraudProofCollateral
        );

        /**
         @notice recording payment claims for the DataLayr operators
         */
        uint32 fromDataStoreId;

        // for the special case of this being the first payment that is being claimed by the DataLayr operator;
        /**
         @notice this special case also implies that the DataLayr operator must be claiming payment from 
                 when the operator registered.   
         */
        if (operatorToPayment[msg.sender].fromDataStoreId == 0) {
            // get the dataStoreId when the DataLayr operator registered
            fromDataStoreId = registry.getFromTaskNumberForOperator(msg.sender);
            require(fromDataStoreId < toDataStoreId, "invalid payment range");

            // record the payment information pertaining to the operator
            operatorToPayment[msg.sender] = Payment(
                fromDataStoreId,
                toDataStoreId,
                uint32(block.timestamp + paymentFraudProofInterval),
                amount,
                // setting to 0 to indicate commitment to payment claim
                PaymentStatus.COMMITTED,
                // storing collateral amount deposited
                paymentFraudProofCollateral
            );

            emit PaymentCommit(msg.sender, fromDataStoreId, toDataStoreId, amount);

            return;
        }

        // you have to redeem starting from the last time redeemed up to
        fromDataStoreId = operatorToPayment[msg.sender].toDataStoreId;
        require(fromDataStoreId < toDataStoreId, "invalid payment range");

        // update the record for the commitment to payment made by the operator
        operatorToPayment[msg.sender] = Payment(
            fromDataStoreId,
            toDataStoreId,
            uint32(block.timestamp + paymentFraudProofInterval),
            amount,
            // set status as 0: committed
            PaymentStatus.COMMITTED,
            paymentFraudProofCollateral
        );

        emit PaymentCommit(msg.sender, fromDataStoreId, toDataStoreId, amount);
    }

    /**
     @notice This function can only be called after the challenge window for the payment claim has completed.
     */
    function redeemPayment() external {
        require(
                block.timestamp > operatorToPayment[msg.sender].confirmAt
                    &&
                operatorToPayment[msg.sender].status == PaymentStatus.COMMITTED,
            "Payment still eligible for fraud proof"
        );

        // update the status to show that operator's payment is getting redeemed
        operatorToPayment[msg.sender].status = PaymentStatus.REDEEMED;

        // transfer back the collateral to the operator as there was no successful
        // challenge to the payment commitment made by the operator.
        collateralToken.safeTransfer(
            msg.sender,
            operatorToPayment[msg.sender].collateral
        );

        ///look up payment amount and delegation terms address for the msg.sender
        uint256 amount = operatorToPayment[msg.sender].amount;

        // check if operator is a self operator, in which case sending payment is simplified
        if (eigenLayrDelegation.isSelfOperator(msg.sender)) {
            //simply transfer the payment amount in this case
            paymentToken.safeTransfer(msg.sender, amount);
        // i.e. if operator is not a 'self operator'
        } else {
            IDelegationTerms dt = eigenLayrDelegation.delegationTerms(msg.sender);
            // transfer the amount due in the payment claim of the operator to its delegation
            // terms contract, where the delegators can withdraw their rewards.
            paymentToken.safeTransfer(address(dt), amount);

            // inform the DelegationTerms contract of the payment, which will determine
            // the rewards operator and its delegators are eligible for
            dt.payForService(paymentToken, amount);
        }

        emit PaymentRedemption(msg.sender, amount);
    }

    /**
    @notice This function would be called by a fraud prover to challenge a payment 
             by initiating an interactive type proof
     **/
    /**
     @param operator is the DataLayr operator against whose payment claim the fraud proof is being made
     @param amount1 is the reward amount the challenger in that round claims is for the first half of dumps
     @param amount2 is the reward amount the challenger in that round claims is for the second half of dumps
     **/
    function challengePaymentInit(
        address operator,
        uint120 amount1,
        uint120 amount2
    ) external {
        
        require(
            block.timestamp < operatorToPayment[operator].confirmAt 
                &&
                operatorToPayment[operator].status == PaymentStatus.COMMITTED,
            "Fraud proof interval has passed"
        );

        // store challenge details
        operatorToPaymentChallenge[operator] = PaymentChallenge(
                operator,
                msg.sender,
                address(dataLayrServiceManager),
                operatorToPayment[operator].fromDataStoreId,
                operatorToPayment[operator].toDataStoreId,
                amount1,
                amount2,
                // recording current timestamp plus the fruad proof interval as the confirmAt
                uint32(block.timestamp + paymentFraudProofInterval),
                ChallengeStatus.OPERATOR_TURN
        );

        //move collateral over
        uint256 collateral = operatorToPayment[operator].collateral;
        collateralToken.safeTransferFrom(msg.sender, address(this), collateral);
        //update payment

        //@TODO: what is payment status = 2?  Definition only has committed or redeemed (aka 0 or 1) @gpsanant
        operatorToPayment[operator].status = PaymentStatus.CHALLENGED;
        operatorToPayment[operator].confirmAt = uint32(block.timestamp + paymentFraudProofInterval);
        emit PaymentChallengeInit(operator, msg.sender);
    }


    //challenger challenges a particular half of the payment
    function challengePaymentHalf(
        address operator,
        bool firstHalf,
        uint120 amount1,
        uint120 amount2
    ) external {
        // copy challenge struct to memory
        PaymentChallenge memory challenge = operatorToPaymentChallenge[operator];

        ChallengeStatus status = challenge.status;

        require(
            (status == ChallengeStatus.CHALLENGER_TURN && challenge.challenger == msg.sender) ||
                (status == ChallengeStatus.OPERATOR_TURN && challenge.operator == msg.sender),
            "Must be challenger and their turn or operator and their turn"
        );

        require(
            block.timestamp < challenge.settleAt,
            "Fraud proof interval has passed"
        );

        uint32 fromDataStoreId = challenge.fromDataStoreId;
        uint32 toDataStoreId = challenge.toDataStoreId;
        uint32 diff;
        //change interval to the one challenger cares about
        // if the difference between the current start and end is even, the new interval has an endpoint halfway inbetween
        // if the difference is odd = 2n + 1, the new interval has a "from" endpoint at (start + n = end - (n + 1)) if the second half is challenged,
        //  or a "to" endpoint at (end - (2n + 1 + 1)/2 = end - (n + 1) = start + n) if the first half is challenged
        if (firstHalf) {
            diff = (toDataStoreId - fromDataStoreId) / 2;
            challenge.fromDataStoreId = fromDataStoreId + diff;
            //if next step is not final
            //TODO: Why are we making this check? Just update status?
            if (updateStatus(operator, diff)) {
                challenge.toDataStoreId = toDataStoreId;
            }
            //TODO: my understanding is that dissection=3 here, not 1 because we are challenging the second half
            updateChallengeAmounts(operator, 3, amount1, amount2);
        } else {
            diff = (toDataStoreId - fromDataStoreId);
            if (diff % 2 == 1) {
                diff += 1;
            }
            diff /= 2;
            //if next step is not final
            //TODO: This saves storage when the next step is final. Why have the second "fromDataStoreLine"?
            if (updateStatus(operator, diff)) {
                challenge.toDataStoreId = toDataStoreId - diff;
                challenge.fromDataStoreId = fromDataStoreId;
            }
            updateChallengeAmounts(operator, 1, amount1, amount2);
        }
        challenge.settleAt = uint32(block.timestamp + paymentFraudProofInterval);

        // update challenge struct in storage
        operatorToPaymentChallenge[operator] = challenge;
        
        emit PaymentBreakdown(operator, challenge.fromDataStoreId, challenge.toDataStoreId, challenge.amount1, challenge.amount2);
    }

    // TODO: change this function to just modify a 'PaymentChallenge' in memory, rather than write to storage? (might save gas)
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
            operatorToPaymentChallenge[operator].status = msg.sender == operator ? ChallengeStatus.CHALLENGER_TURN_ONE_STEP : ChallengeStatus.OPERATOR_TURN_ONE_STEP;
            return false;

        // payment challenge across more than one data dump
        } else {
            // set to dissection turn of either challenger or operator
            operatorToPaymentChallenge[operator].status = msg.sender == operator ? ChallengeStatus.CHALLENGER_TURN : ChallengeStatus.OPERATOR_TURN;
            return true;
        }
   }


// TODO: change this function to just modify a 'PaymentChallenge' in memory, rather than write to storage? (might save gas)
    //an operator can respond to challenges and breakdown the amount
    function updateChallengeAmounts(
        address operator, 
        uint8 disectionType,
        uint120 amount1,
        uint120 amount2
    ) internal {
        if (disectionType == 1) {
            //if first half is challenged, break the first half of the payment into two halves
            require(
                amount1 + amount2 != operatorToPaymentChallenge[operator].amount1,
                "Invalid amount bbbreakdown"
            );
        } else if (disectionType == 3) {
            //if second half is challenged, break the second half of the payment into two halves
            require(
                amount1 + amount2 != operatorToPaymentChallenge[operator].amount2,
                "Invalid amount breakdown"
            );
        } else {
            revert("Not in operator challenge phase");
        }
        operatorToPaymentChallenge[operator].amount1 = amount1;
        operatorToPaymentChallenge[operator].amount2 = amount2;
    }

    function resolveChallenge(address operator) public {
        // copy challenge struct to memory
        PaymentChallenge memory challenge = operatorToPaymentChallenge[operator];

        uint256 interval = paymentFraudProofInterval;
        require(
            block.timestamp > challenge.settleAt &&
                block.timestamp < challenge.settleAt + interval,
            "Fraud proof interval has passed"
        );
        ChallengeStatus status = challenge.status;
        if (status == ChallengeStatus.OPERATOR_TURN || status == ChallengeStatus.OPERATOR_TURN_ONE_STEP) {
            // operator did not respond
            resolve(challenge, challenge.challenger);
        } else if (status == ChallengeStatus.CHALLENGER_TURN || status == ChallengeStatus.CHALLENGER_TURN_ONE_STEP) {
            // challenger did not respond
            resolve(challenge, challenge.operator);
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
            "Fraud proof interval has passed"
        );

        uint32 challengedDataStoreId = challenge.fromDataStoreId;
        ChallengeStatus status = challenge.status;

        require(dataLayrServiceManager.getDataStoreHashesForDurationAtTimestamp(
                searchData.duration, 
                searchData.timestamp,
                searchData.index
            ) == DataStoreHash.computeDataStoreHash(searchData.metadata), "search.metadata preimage is incorrect");

        IQuorumRegistry registry = IQuorumRegistry(address(repository.registry()));

        bytes32 operatorPubkeyHash = registry.getOperatorPubkeyHash(operator);

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
            IQuorumRegistry.OperatorStake memory operatorStake = registry.getStakeFromPubkeyHashAndIndex(operatorPubkeyHash, stakeIndex);

            // scoped block helps fix stack too deep
            {
                // (uint32 dataStoreIdFromHeaderHash, , , uint32 challengedDumpBlockNumber) = (dataLayrServiceManager.dataLayr()).dataStores(challengedDumpHeaderHash);
                // require(dataStoreIdFromHeaderHash == challengedDataStoreId, "specified dataStoreId does not match provided headerHash");
                require(
                    operatorStake.updateBlockNumber <= searchData.metadata.blockNumber,
                    "Operator stake index is too late"
                );

                require(
                    operatorStake.nextUpdateBlockNumber == 0 ||
                        operatorStake.nextUpdateBlockNumber > searchData.metadata.blockNumber,
                    "Operator stake index is too early"
                );
            }

            //TODO: Change this
            IDataLayrServiceManager.DataStoreMetadata memory metadata = searchData.metadata;
            require(metadata.globalDataStoreId == challengedDataStoreId, "Loaded DataStoreId does not match challenged");

            //TODO: assumes even eigen eth split
            trueAmount = uint120(
                (metadata.fee * operatorStake.ethStake) /
                    totalStakes.ethStakeSigned /
                    2 +
                    (metadata.fee * operatorStake.eigenStake) /
                    totalStakes.eigenStakeSigned /
                    2
            );
        } else {
            //either the operator must have been a non signer or the task was based off of stakes before the operator registered
            require(
                nonSignerPubkeyHashes[nonSignerIndex] == operatorPubkeyHash
                || searchData.metadata.blockNumber < registry.getFromBlockNumberForOperator(operator),
                "Signer index is incorrect"
            );
        }

        bool finalEntityCorrect = trueAmount != challenge.amount1;
        /*
        * if status is OPERATOR_TURN_ONE_STEP, it is the operator's turn. This means the challenger was the one who set challenge.amount1 last.  
        * If trueAmount != challenge.amount1, then the challenger is wrong (doesn't mean operator is right).
        */
        if (status == ChallengeStatus.OPERATOR_TURN_ONE_STEP) {
            resolve(challenge, finalEntityCorrect ? challenge.operator : challenge.challenger);
        } 
        /*
        * if status is CHALLENGER_TURN_ONE_STEP, it is the challenger's turn. This means the operator was the one who set challenge.amount1 last.  
        * If trueAmount == challenge.amount1, then the operator is correct and the challenger is wrong
        */
        
        else if (status == ChallengeStatus.CHALLENGER_TURN_ONE_STEP) {
            resolve(challenge, !finalEntityCorrect ? challenge.challenger : challenge.operator);
        } else {
            revert("Not in one step challenge phase");
        }

        challenge.status = ChallengeStatus.RESOLVED;

        // update challenge struct in storage
        operatorToPaymentChallenge[operator] = challenge;
    }

// TODO: verify that the amounts used in this function are appropriate!
    /* 
    @notice: resolve payment challenge
    
    @param winner is the party who wins the challenge, either the challenger or the operator
    @param operatorSuccessful is true when the operator wins the challenge agains the challenger
    */
    function resolve(PaymentChallenge memory challenge, address winner) internal {
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
            //give them their collateral and the operators
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

    function getPaymentCollateral(address operator)
        public
        view
        returns (uint256)
    {
        return operatorToPayment[operator].collateral;
    }

    function dataStoreId() internal view returns (uint32) {
        return dataLayrServiceManager.taskNumber();
    }
}
