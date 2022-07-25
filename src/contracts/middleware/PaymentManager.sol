// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IRepository.sol";
import "../interfaces/IServiceManager.sol";
import "../interfaces/IQuorumRegistry.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IPaymentManager.sol";
import "./Repository.sol";
import "../permissions/RepositoryAccess.sol";

import "ds-test/test.sol";

/**
 @notice This contract is used for doing interactive payment challenge.
 */


contract PaymentManager is 
    RepositoryAccess, 
    IPaymentManager
    // ,DSTest 
    {
    /**********************
     DATA STRUCTURES
     **********************/

    /**
      @notice used for storing information on the most recent payment made to the operator
     */
    struct Payment {
        // taskNumber starting from which payment is being claimed 
        uint32 fromTaskNumber; 

        // taskNumber until which payment is being claimed (exclusive) 
        uint32 toTaskNumber; 

        // recording when committment for payment made; used for fraud proof period
        uint32 commitTime; 

        // payment for range [fromTaskNumber, toTaskNumber)
        /// @dev max 1.3e36, keep in mind for token decimals
        uint120 amount; 

        uint8 status; // 0: committed, 1: redeemed

        uint256 collateral; //account for if collateral changed
    }

    /**
      @notice used for storing information on the payment challenge as part of the interactive process
     */
    struct PaymentChallenge {
        // operator whose payment claim is being challenged,
        address operator;

        // the entity challenging with the fraudproof
        address challenger;

        // address of the service manager contract
        address serviceManager;

        // the TaskNumber from which payment has been computed
        uint32 fromTaskNumber;

        // the TaskNumber until which payment has been computed to
        uint32 toTaskNumber;

        // reward amount the challenger claims is for the first half of tasks
        uint120 amount1;

        // reward amount the challenger claims is for the second half of tasks
        uint120 amount2;

        // used for recording the time when challenge was created
        uint32 commitTime; // when committed, used for fraud proof period


        // indicates the status of the challenge
        /**
         @notice The possible status are:
                    - 0: committed,
                    - 1: redeemed,
                    - 2: operator turn (dissection),
                    - 3: challenger turn (dissection),
                    - 4: operator turn (one step),
                    - 5: challenger turn (one step)
         */
        uint8 status;   
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

// TODO: set this value
    /**
     @notice this is the payment that has to be made as a collateral for fraudproof 
             during payment challenges
     */
    uint256 public paymentFraudProofCollateral = 1 wei;

    /**
     * @notice the ERC20 token that will be used by the disperser to pay the service fees to
     *         middleware nodes.
     */
    IERC20 public immutable paymentToken;

    // collateral token used for placing collateral on challenges & payment commits
    IERC20 public immutable collateralToken;

    /**
     * @notice The EigenLayr delegation contract for this middleware which is primarily used by
     *      delegators to delegate their stake to operators who would serve as middleware
     *      nodes and so on.
     */
    /**
      @dev For more details, see EigenLayrDelegation.sol. 
     */
    IEigenLayrDelegation public immutable eigenLayrDelegation;

    /**
        @notice mapping between the operator and its current committed payment
        or last redeemed payment 
    */
    mapping(address => Payment) public operatorToPayment;

    // operator => PaymentChallenge
    mapping(address => PaymentChallenge) public operatorToPaymentChallenge;

    // deposits of future fees to be drawn against when paying for taking service for the task
    mapping(address => uint256) public depositsOf;

    // depositors => addresses approved to spend deposits => allowance
    mapping(address => mapping(address => uint256)) public allowances;




    /******** 
     EVENTS
     ********/
    event PaymentCommit(
        address operator,
        uint32 fromTaskNumber,
        uint32 toTaskNumber,
        uint256 fee
    );
    event PaymentRedemption(address operator, uint256 fee);

    event PaymentBreakdown(uint32 fromTaskNumber, uint32 toTaskNumber, uint120 amount1, uint120 amount2);

    event PaymentChallengeInit(address operator, address challenger);

    event PaymentChallengeResolution(address operator, bool operatorWon);



    constructor(
        IERC20 _paymentToken,
        IRepository _repository
    )   
        // set repository address equal to that of serviceManager
        RepositoryAccess(_repository) 
    {
        paymentToken = _paymentToken;
        IServiceManager _serviceManager = _repository.serviceManager();
        collateralToken = _serviceManager.collateralToken();
        eigenLayrDelegation = _serviceManager.eigenLayrDelegation();
    }


    /**
     @notice deposit one-time fees by the middleware with this contract for set number of tasks 
     */
    /**
     @param onBehalfOf could be the msg.sender or someone lese who is depositing 
     this future fees           
     */ 
    function depositFutureFees(address onBehalfOf, uint256 amount) external {
        paymentToken.transferFrom(msg.sender, address(this), amount);
        depositsOf[onBehalfOf] += amount;
    }


    function setPermanentAllowance(address allowed, uint256 amount) public {
        allowances[msg.sender][allowed] = amount;
    }


    /**
     @notice Used for deducting the fees from the payer to the 
     */
    function payFee(address initiator, address payer, uint256 feeAmount) external onlyServiceManager {
        //todo: can this be a permanent allowance? decreases an sstore per fee paying.
        // NOTE: (from JEFFC) this currently *is* a persistant/permanent allowance, as it isn't getting decreased anywhere
        if(initiator != payer){
            require(allowances[payer][initiator] >= feeAmount, "initiator not allowed to spend payers balance");
        }

        depositsOf[payer] -= feeAmount;
    }



    function setPaymentFraudProofCollateral(
        uint256 _paymentFraudProofCollateral
    ) public onlyRepositoryGovernance {
        paymentFraudProofCollateral = _paymentFraudProofCollateral;
    }

    /**
     @notice This is used by an operator to make claim on the @param amount that they deserve 
             for their service since their last payment until @param toTaskNumber  
     */
    function commitPayment(uint32 toTaskNumber, uint120 amount) external {
        IQuorumRegistry registry = IQuorumRegistry(address(repository.registry()));

        // only registered operators can call
        require(
            registry.getOperatorType(msg.sender) != 0,
            "Only registered operators can call this function"
        );

        require(toTaskNumber <= taskNumber(), "Cannot claim future payments");

        // operator puts up collateral which can be slashed in case of wrongful payment claim
        collateralToken.transferFrom(
            msg.sender,
            address(this),
            paymentFraudProofCollateral
        );



        /********************
         recording payment claims for the operator
         ********************/

        uint32 fromTaskNumber;

        // for the special case of this being the first payment that is being claimed by the operator;
        /**
         @notice this special case also implies that the operator must be claiming payment from 
                 when the operator registered.   
         */
        if (operatorToPayment[msg.sender].fromTaskNumber == 0) {

            // get the taskNumber when the operator registered
            fromTaskNumber = registry.getFromTaskNumberForOperator(msg.sender);
            require(fromTaskNumber < toTaskNumber, "invalid payment range");

            // record the payment information pertaining to the operator
            operatorToPayment[msg.sender] = Payment(
                fromTaskNumber,
                toTaskNumber,
                uint32(block.timestamp),
                amount,
                // setting to 0 to indicate commitment to payment claim
                0,
                paymentFraudProofCollateral
            );

            emit PaymentCommit(msg.sender, fromTaskNumber, toTaskNumber, amount);

            return;
        }

        // can only claim for a payment after redeeming the last payment
        require(
            operatorToPayment[msg.sender].status == 1,
            "Require last payment is redeemed"
        );

        // you have to redeem starting from the last time redeemed up to
        fromTaskNumber = operatorToPayment[msg.sender].toTaskNumber;
        require(fromTaskNumber < toTaskNumber, "invalid payment range");

        // update the record for the commitment to payment made by the operator
        operatorToPayment[msg.sender] = Payment(
            fromTaskNumber,
            toTaskNumber,
            uint32(block.timestamp),
            amount,
            // set status as 0: committed
            0,
            paymentFraudProofCollateral
        );

        emit PaymentCommit(msg.sender, fromTaskNumber, toTaskNumber, amount);
    }

    /**
     @notice This function can only be called after the challenge window for the payment claim has completed.
     */
    function redeemPayment() external {
        require(
            block.timestamp >
                (operatorToPayment[msg.sender].commitTime +
                    paymentFraudProofInterval) &&
                operatorToPayment[msg.sender].status == 0,
            "Payment still eligible for fraud proof"
        );

        // update the status to show that operator's payment is getting redeemed
        operatorToPayment[msg.sender].status = 1;

        // transfer back the collateral to the operator as there was no successful
        // challenge to the payment commitment made by the operator.
        collateralToken.transfer(
            msg.sender,
            operatorToPayment[msg.sender].collateral
        );

        ///look up payment amount and delegation terms address for the msg.sender
        uint256 amount = operatorToPayment[msg.sender].amount;

        // check if operator is a self operator, in which case sending payment is simplified
        if (eigenLayrDelegation.isSelfOperator(msg.sender)) {
            //simply transfer the payment amount in this case
            paymentToken.transfer(msg.sender, amount);
        // i.e. if operator is not a 'self operator'
        } else {
            IDelegationTerms dt = eigenLayrDelegation.delegationTerms(msg.sender);
            // transfer the amount due in the payment claim of the operator to its delegation
            // terms contract, where the delegators can withdraw their rewards.
            paymentToken.transfer(address(dt), amount);

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
     @param operator is the operator against whose payment claim the fraud proof is being made
     @param amount1 is the reward amount the challenger in that round claims is for the first half of tasks
     @param amount2 is the reward amount the challenger in that round claims is for the second half of tasks
     **/
    function challengePaymentInit(
        address operator,
        uint120 amount1,
        uint120 amount2
    ) external {
        
        require(
            block.timestamp <
                operatorToPayment[operator].commitTime +
                    paymentFraudProofInterval &&
                operatorToPayment[operator].status == 0,
            "Fraud proof interval has passed"
        );

        // store challenge details
        operatorToPaymentChallenge[operator] = PaymentChallenge(
                operator,
                msg.sender,
                address(repository.serviceManager()),
                operatorToPayment[operator].fromTaskNumber,
                operatorToPayment[operator].toTaskNumber,
                amount1,
                amount2,
                // recording current timestamp as the commitTime
                uint32(block.timestamp),
                // setting operator to respond next
                uint8(2)
        );

        //move collateral over
        uint256 collateral = operatorToPayment[operator].collateral;
        collateralToken.transferFrom(msg.sender, address(this), collateral);
        //update payment
        operatorToPayment[operator].status = 2;
        operatorToPayment[operator].commitTime = uint32(block.timestamp);
        emit PaymentChallengeInit(operator, msg.sender);
    }


    //challenger challenges a particular half of the payment
    function challengePaymentHalf(
        address operator,
        bool half,
        uint120 amount1,
        uint120 amount2
    ) external {
        // copy challenge struct to memory
        PaymentChallenge memory challenge = operatorToPaymentChallenge[operator];

        uint8 status = challenge.status;

        require(
            (status == 3 && challenge.challenger == msg.sender) ||
                (status == 2 && challenge.operator == msg.sender),
            "Must be challenger and their turn or operator and their turn"
        );


        require(
            block.timestamp <
                challenge.commitTime + paymentFraudProofInterval,
            "Fraud proof interval has passed"
        );


        uint32 fromTaskNumber = challenge.fromTaskNumber;
        uint32 toTaskNumber = challenge.toTaskNumber;
        uint32 diff;
        
        //change interval to the one challenger cares about
        // if the difference between the current start and end is even, the new interval has an endpoint halfway inbetween
        // if the difference is odd = 2n + 1, the new interval has a "from" endpoint at (start + n = end - (n + 1)) if the second half is challenged,
        //  or a "to" endpoint at (end - (2n + 2)/2 = end - (n + 1) = start + n) if the first half is challenged
        if (half) {
            diff = (toTaskNumber - fromTaskNumber) / 2;
            challenge.fromTaskNumber = fromTaskNumber + diff;
            //if next step is not final
            if (updateStatus(operator, diff)) {
                challenge.toTaskNumber = toTaskNumber;
            }
            //TODO: my understanding is that dissection=3 here, not 1 because we are challenging the second half
            updateChallengeAmounts(operator, 3, amount1, amount2);
        } else {
            diff = (toTaskNumber - fromTaskNumber);
            if (diff % 2 == 1) {
                diff += 1;
            }
            diff /= 2;
            //if next step is not final
            if (updateStatus(operator, diff)) {
                challenge.toTaskNumber = toTaskNumber - diff;
                challenge.fromTaskNumber = fromTaskNumber;
            }
            updateChallengeAmounts(operator, 1, amount1, amount2);
        }
        challenge.commitTime = uint32(block.timestamp);

        // update challenge struct in storage
        operatorToPaymentChallenge[operator] = challenge;
        
        emit PaymentBreakdown(challenge.fromTaskNumber, challenge.toTaskNumber, challenge.amount1, challenge.amount2);
    }



// TODO: change this function to just modify a 'PaymentChallenge' in memory, rather than write to storage? (might save gas)
    /**
     @notice This function is used for updating the status of the challenge in terms of who
             has to respond to the interactive challenge mechanism next -  is it going to be
             challenger or the operator.   
     */
    /**
     @param operator is the operator whose payment claim is being challenged
     @param diff is the number of tasks across which payment is being challenged in this iteration
     */ 
    function updateStatus(address operator, uint32 diff)
        internal
        returns (bool)
    {
        // copy challenge struct to memory
        PaymentChallenge memory challenge = operatorToPaymentChallenge[operator];

        // payment challenge for one data dump
        if (diff == 1) {
            //set to one step turn of either challenger or operator
            challenge.status = (msg.sender == operator ? 5 : 4);
            return false;

        // payment challenge across more than one data dump
        } else {
            // set to dissection turn of either challenger or operator
            challenge.status = (msg.sender == operator ? 3 : 2);
            return true;
        }

        // update challenge struct in storage
        operatorToPaymentChallenge[operator] = challenge;
   }


// TODO: change this function to just modify a 'PaymentChallenge' in memory, rather than write to storage? (might save gas)
    //an operator can respond to challenges and breakdown the amount
    function updateChallengeAmounts(
        address operator, 
        uint8 disectionType,
        uint120 amount1,
        uint120 amount2
    ) internal {
        // copy challenge struct to memory
        PaymentChallenge memory challenge = operatorToPaymentChallenge[operator];

        if (disectionType == 1) {
            //if first half is challenged, break the first half of the payment into two halves
            require(
                amount1 + amount2 == challenge.amount1,
                "Invalid amount breakdown"
            );
        } else if (disectionType == 3) {
            //if second half is challenged, break the second half of the payment into two halves
            require(
                amount1 + amount2 == challenge.amount2,
                "Invalid amount breakdown"
            );
        } else {
            revert("Not in operator challenge phase");
        }
        challenge.amount1 = amount1;
        challenge.amount2 = amount2;

        // update challenge struct in storage
        operatorToPaymentChallenge[operator] = challenge;
    }

    function resolveChallenge(address operator) public {
        // copy challenge struct to memory
        PaymentChallenge memory challenge = operatorToPaymentChallenge[operator];

        uint256 interval = paymentFraudProofInterval;
        require(
            block.timestamp > challenge.commitTime + interval &&
                block.timestamp < challenge.commitTime + (2 * interval),
            "Fraud proof interval has passed"
        );
        uint8 status = challenge.status;
        if (status == 2 || status == 4) {
            // operator did not respond
            resolve(operator, false);
        } else if (status == 3 || status == 5) {
            // challenger did not respond
            resolve(operator, true);
        }
    }
// TODO: get this working
/*
    //an operator can respond to challenges and breakdown the amount
    function respondToPaymentChallengeFinal(
        address operator,
        uint256 stakeIndex,
        uint48 nonSignerIndex,
        bytes32[] memory nonSignerPubkeyHashes,
        TotalStakes calldata totalStakes,
        bytes32 challengedHeaderHash,
        IServiceManager.DataStoreSearchData calldata searchData
    ) external {
        // copy challenge struct to memory
        PaymentChallenge memory challenge = operatorToPaymentChallenge[operator];

        require(
            block.timestamp <
                challenge.commitTime + paymentFraudProofInterval,
            "Fraud proof interval has passed"
        );
        uint32 challengedTaskNumber = challenge.fromTaskNumber;
        uint8 status = challenge.status;
        //check sigs
        require(
            serviceManager.getTaskNumberSignatureHash(challengedTaskNumber) ==
                keccak256(
                    abi.encodePacked(
                        challengedTaskNumber,
                        nonSignerPubkeyHashes,
                        totalStakes.ethStakeSigned,
                        totalStakes.eigenStakeSigned
                    )
                ),
            "Sig record does not match hash"
        );

        IRegistry registry = repository.registry();

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
            (uint32 taskNumberFromHeaderHash, , , uint32 challengedDumpBlockNumber) = (serviceManager.dataLayr()).dataStores(challengedHeaderHash);
            require(taskNumberFromHeaderHash == challengedTaskNumber, "specified taskNumber does not match provided headerHash");
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
            require(serviceManager.getTaskNumbersForDuration(
                searchData.duration, 
                searchData.timestamp
            ) == hashLinkedDataStoreMetadatas(searchData.metadatas), "search.metadatas preimage is incorrect");

            //TODO: Change this
            IServiceManager.DataStoreMetadata memory metadata = searchData.metadatas[searchData.index];
            require(metadata.globalTaskNumber == challengedTaskNumber, "Loaded TaskNumber does not match challenged");

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
            require(
                nonSignerPubkeyHashes[nonSignerIndex] == operatorPubkeyHash,
                "Signer index is incorrect"
            );
        }

        if (status == 4) {
            resolve(operator, trueAmount != challenge.amount1);
        } else if (status == 5) {
            resolve(operator, trueAmount == challenge.amount1);
        } else {
            revert("Not in one step challenge phase");
        }
        challenge.status = 1;

        // update challenge struct in storage
        operatorToPaymentChallenge[operator] = challenge;
    }
*/
    /*
    @notice: resolve payment challenge
    */
    function resolve(address operator, bool challengeSuccessful) internal {
        if (challengeSuccessful) {
            // operator was correct, allow for another challenge
            operatorToPayment[operator].status = 0;
            operatorToPayment[operator].commitTime = uint32(block.timestamp);
            //give them previous challengers collateral
            collateralToken.transfer(
                operator,
                operatorToPayment[operator].collateral
            );
            emit PaymentChallengeResolution(operator, true);
        } else {
            // challeger was correct, reset payment
            operatorToPayment[operator].status = 1;
            //give them their collateral and the operators
            collateralToken.transfer(
                operator,
                2 * operatorToPayment[operator].collateral
            );
            emit PaymentChallengeResolution(operator, false);
        }
    }

    function getChallengeStatus(address operator) external view returns(uint8) {
        return operatorToPaymentChallenge[operator].status;
    }

    function getAmount1(address operator) external view returns (uint120) {
        return operatorToPaymentChallenge[operator].amount1;
    }

    function getAmount2(address operator) external view returns (uint120) {
        return operatorToPaymentChallenge[operator].amount2;
    }

    function getToTaskNumber(address operator) external view returns (uint48) {
        return operatorToPaymentChallenge[operator].toTaskNumber;
    }

    function getFromTaskNumber(address operator) external view returns (uint48) {
        return operatorToPaymentChallenge[operator].fromTaskNumber;
    }

    function getDiff(address operator) external view returns (uint48) {
        return operatorToPaymentChallenge[operator].toTaskNumber - operatorToPaymentChallenge[operator].fromTaskNumber;
    }

    function getPaymentCollateral(address operator)
        public
        view
        returns (uint256)
    {
        return operatorToPayment[operator].collateral;
    }

    function taskNumber() internal view returns (uint32) {
        return repository.serviceManager().taskNumber();
    }

// TODO: delete or replace with general solution
/*
    function hashLinkedDataStoreMetadatas(IServiceManager.DataStoreMetadata[] memory metadatas) internal pure returns(bytes32) {
        bytes32 res = bytes32(0);
        for(uint i = 0; i < metadatas.length; i++) {
            res = keccak256(abi.encodePacked(res, metadatas[i].durationTaskNumber, metadatas[i].globalTaskNumber, metadatas[i].fee));
        }
        return res;
    }
*/
}
