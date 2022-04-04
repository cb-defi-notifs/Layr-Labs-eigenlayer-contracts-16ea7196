// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IQueryManager.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/ProofOfStakingInterfaces.sol";
import "../../interfaces/IDelegationTerms.sol";
import "./storage/DataLayrServiceManagerStorage.sol";
import "./DataLayrPaymentChallenge.sol";
import "./DataLayrSignatureChecker.sol";
import "../QueryManager.sol";


/**
 * @notice 
 */
contract DataLayrServiceManager is
    DataLayrSignatureChecker,
    IProofOfStakingOracle
{
    /**
     * @dev The EigenLayr delegation contract for this DataLayr which primarily used by 
     *      delegators to delegate their stake to operators who would serve as DataLayr 
     *      nodes and so on. For more details, see EigenLayrDelegation.sol.  
     */   
    IEigenLayrDelegation public immutable eigenLayrDelegation;

    /**
     * @notice the ERC20 token that will be used by the disperser to pay the service fees to
     *         DataLayr nodes. 
     */
    IERC20 public immutable paymentToken;



    IERC20 public immutable collateralToken;


    // EVENTS
    /**
     * @notice used for notifying that disperser has initiated a data assertion into the 
     *         DataLayr and is waiting for getting a quorum of DataLayr nodes to sign on it. 
     */

    event PaymentCommit(address operator, uint48 fromDumpNumber, uint48 toDumpNumber, uint256 fee);

    event PaymentChallengeInit(address operator, address challenger);

    event PaymentChallengeResolution(address operator, bool operatorWon);

    event PaymentRedemption(address operator, uint256 fee);

    constructor(
        IEigenLayrDelegation _eigenLayrDelegation,
        IERC20 _paymentToken,
        IERC20 _collateralToken,
        uint256 _feePerBytePerTime
    ) {
        eigenLayrDelegation = _eigenLayrDelegation;
        paymentToken = _paymentToken;
        collateralToken = _collateralToken;
        feePerBytePerTime = _feePerBytePerTime;
    }

    modifier onlyQMGovernance() {
        require(
            queryManager.timelock() == msg.sender,
            "Query Manager governance can only call this function"
        );
        _;
    }

    function setQueryManager(IQueryManager _queryManager) public {
        require(
            address(queryManager) == address(0),
            "Query Manager already set"
        );
        queryManager = _queryManager;


        dlRegVW = IDataLayrVoteWeigher(
            address(queryManager.voteWeighter())
        );
    }

    /**
     * @notice This function is used for 
     *          - notifying in the settlement layer that the disperser has asserted the data 
     *            into DataLayr and is waiting for obtaining quorum of DataLayr nodes to sign,
     *          - asserting the metadata corresponding to the data asserted into DataLayr
     *          - escrow the service fees that DataLayr nodes will receive from the disperser 
     *            on account of their service.  
     */
    /**
     * @param ferkleRoot is the commitment to the data that is being asserted into DataLayr,
     * @param storePeriodLength for which the data has to be stored by the DataLayr nodes, 
     * @param totalBytes  is the size of the data ,
     */
    function initDataStore(
        address storer,
        bytes32 ferkleRoot,
        uint32 totalBytes,
        uint32 storePeriodLength
    ) external payable {
        require(
            msg.sender == address(queryManager),
            "Only the query manager can call this function"
        );

        require(totalBytes > 32, "Can't store less than 33 bytes");

        require(storePeriodLength > 60, "store for more than a minute");

        require(storePeriodLength < 604800, "store for less than 7 days");

        // evaluate the total service fees that disperser has to put in escrow for paying out 
        // the DataLayr nodes for their service
        uint256 fee = totalBytes * storePeriodLength * feePerBytePerTime;

        // increment the counter
        dumpNumber++;

        // record the total service fee that will be paid out for this assertion of data
        dumpNumberToFee[dumpNumber] = fee;

        // recording the expiry time until which the DataLayr nodes, who sign up to 
        // part of the quorum, have to store the data
        IDataLayrVoteWeigher(address(queryManager.voteWeighter()))
            .setLatestTime(uint32(block.timestamp) + storePeriodLength);


        // escrow the total service fees from the disperser to the DataLayr nodes in this contract
        // CRITIC: change "storer" to "disperser"?
        paymentToken.transferFrom(storer, address(this), fee);


        // call DL contract
        dataLayr.initDataStore(
            dumpNumber,
            ferkleRoot,
            totalBytes,
            storePeriodLength
        );
    }


    /**
     * @notice This function is used for 
     *          - disperser to notify that signatures on the message, comprising of hash( ferkleroot ),
     *            from quorum of DataLayr nodes have been obtained,
     *          - check that each of the signatures are valid,
     *          - call the DataLayr contract to check that whether quorum has been achieved or not.     
     */
    /**
     * @param data TBA.
     */ 
    // CRITIC: there is an important todo in this function
    function confirmDataStore(bytes calldata data) external payable {
        require(
            msg.sender == address(queryManager),
            "Only the query manager can call this function"
        );

        // verify the signatures that disperser is claiming to be that of DataLayr nodes
        // who have agreed to be in the quorum
        (
            uint48 dumpNumberToConfirm,
            bytes32 ferkleRoot,
            SignatoryTotals memory signedTotals,
            bytes32 signatoryRecordHash
        ) = checkSignatures(data);

        /**
         * @dev Checks that there is no need for posting a deposit root required for proving 
         * the new staking of ETH into settlement layer after the launch of EigenLayr. For 
         * more details, see "depositPOSProof" in EigenLayrDeposit.sol. 
         */
        require(dumpNumberToConfirm % depositRootInterval != 0, "Must post a deposit root now");
        
        // record the compressed information on all the DataLayr nodes who signed 
        dumpNumberToSignatureHash[dumpNumberToConfirm] = signatoryRecordHash;

        // call DataLayr contract to check whether quorum is satisfied or not and record it
        dataLayr.confirm(
            dumpNumberToConfirm,
            ferkleRoot,
            signedTotals.ethStakeSigned,
            signedTotals.eigenStakeSigned,
            signedTotals.totalEthStake,
            signedTotals.totalEigenStake
        );
    }


    /**
     * @notice This function is used when the enshrined DataLayr is used to update the POSt hash
     *         along with the regular assertion of data into the DataLayr by the disperser. This 
     *         function enables 
     *          - disperser to notify that signatures, comprising of hash(depositRoot || ferkleRoot),
     *            from quorum of DataLayr nodes have been obtained,
     *          - check that each of the signatures are valid,
     *          - store the POSt hash, given by depositRoot,
     *          - call the DataLayr contract to check that whether quorum has been achieved or not.      
     */
    function confirmDataStoreWithPOSt(
        bytes32 depositRoot, 
        bytes32 ferkleRoot, 
        bytes calldata data
    ) external payable {
        require(
            msg.sender == address(queryManager),
            "Only the query manager can call this function"
        );
        (
            uint48 dumpNumberToConfirm,
            bytes32 depositFerkleHash,
            SignatoryTotals memory signedTotals,
            bytes32 signatoryRecordHash
        ) = checkSignatures(data);

        /**
         * @dev Checks that there is need for posting a deposit root required for proving 
         * the new staking of ETH into settlement layer after the launch of EigenLayr. For 
         * more details, see "depositPOSProof" in EigenLayrDeposit.sol. 
         */
        require(dumpNumberToConfirm % depositRootInterval == 0, "Shouldn't post a deposit root now");

        // record the compressed information on all the DataLayr nodes who signed 
        dumpNumberToSignatureHash[dumpNumberToConfirm] = signatoryRecordHash;
        
        /**
         * when posting a deposit root, DataLayr nodes will sign hash(depositRoot || ferkleRoot)
         * instead of the usual ferkleRoot, so the submitter must specify the preimage
         */
        require(keccak256(abi.encodePacked(depositRoot, ferkleRoot)) == depositFerkleHash, "Ferkle or deposit root is incorrect");
        
        // record the deposit root (POSt hash)
        depositRoots[block.number] = depositRoot;

        // call DataLayr contract to check whether quorum is satisfied or not and record it
        // CRITIC: not to use tx.origin as it is a dangerous practice
        dataLayr.confirm(
            dumpNumberToConfirm,
            ferkleRoot,
            signedTotals.ethStakeSigned,
            signedTotals.eigenStakeSigned,
            signedTotals.totalEthStake,
            signedTotals.totalEigenStake
        );
    }

    //an operator can commit that they deserve `amount` payment for their service since their last payment to toDumpNumber
    // TODO: collateral
    /**
     * @notice 
     */
    function commitPayment(uint48 toDumpNumber, uint120 amount) external {
        // only registered operators can call
        require(
            queryManager.getOperatorType(msg.sender) != 0,
            "Only registered operators can call this function"
        );

        require(toDumpNumber <= dumpNumber, "Cannot claim future payments");

        // operator puts up collateral which can be slashed in case of wrongful 
        // payment claim
        collateralToken.transferFrom(
            msg.sender,
            address(this),
            paymentFraudProofCollateral
        );

        uint48 fromDumpNumber;

        if (operatorToPayment[msg.sender].fromDumpNumber == 0) {
            // this is the first commitment to a payment and thus, it must be claiming 
            // payment from when the operator registered

            // get the dumpNumber in the DataLayr when the operator registered
            fromDumpNumber = IDataLayrVoteWeigher(
                address(queryManager.voteWeighter())
            ).getOperatorFromDumpNumber(msg.sender);

            require(fromDumpNumber < toDumpNumber, "invalid payment range");

            // record the payment information for the operator
            operatorToPayment[msg.sender] = Payment(
                fromDumpNumber,
                toDumpNumber,
                uint32(block.timestamp),
                amount,
                0,
                paymentFraudProofCollateral
            );

            return;
        }

        // can only claim for a payment after redeeming the last payment
        require(
            operatorToPayment[msg.sender].status == 1,
            "Require last payment is redeemed"
        );

        // you have to redeem starting from the last time redeemed up to
        fromDumpNumber = operatorToPayment[msg.sender].toDumpNumber;

        require(fromDumpNumber < toDumpNumber, "invalid payment range");
        
        // update the record for the commitment to payment made by the operator
        operatorToPayment[msg.sender] = Payment(
            fromDumpNumber,
            toDumpNumber,
            uint32(block.timestamp),
            amount,
            0,
            paymentFraudProofCollateral
        );

        emit PaymentCommit(msg.sender, fromDumpNumber, toDumpNumber, amount);
    }


    // can only call after challenge window
    function redeemPayment() external {
        require(
            block.timestamp >
                operatorToPayment[msg.sender].commitTime +
                    paymentFraudProofInterval &&
                operatorToPayment[msg.sender].status == 0,
            "Still eligible for fraud proofs"
        );

        // update the status to show that operator's payment is getting redeemed
        operatorToPayment[msg.sender].status = 1;

        // transfer back the collateral to the operator as there was no successful 
        // challenge to the payment commitment made by the operator.
        collateralToken.transfer(
            msg.sender,
            operatorToPayment[msg.sender].collateral
        );

        // transfer the amount due in the payment claim of the operator to its delegation
        // terms contract, where the delegators can withdraw their rewards. 
        uint256 amount = operatorToPayment[msg.sender].amount;
        IDelegationTerms dt = eigenLayrDelegation.getDelegationTerms(msg.sender);
        paymentToken.transfer(address(dt), amount);


        // i.e. if operator is not a 'self operator'
        // CRITIC: The self-operators seem to pass this test too as for self-operators
        //         address(dt) = address(0).  
        if (address(dt) == msg.sender) {
            // inform the DelegationTerms contract of the payment, which would determine
            // the rewards operator and its delegators are eligible for
            dt.payForService(paymentToken, amount);            
        }

        emit PaymentRedemption(msg.sender, amount);
    }

    //a fraud prover can challenge a payment to initiate an interactive arbitrum type proof
    //TODO: How much collateral
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
        // deploy new challenge contract
        address challengeContract = address(
            new DataLayrPaymentChallenge(
                operator,
                msg.sender,
                operatorToPayment[operator].fromDumpNumber,
                operatorToPayment[operator].toDumpNumber,
                amount1,
                amount2
            )
        );
        //move collateral over
        uint256 collateral = operatorToPayment[operator].collateral;
        collateralToken.transferFrom(msg.sender, address(this), collateral);
        //update payment
        operatorToPayment[operator].status = 2;
        operatorToPayment[operator].commitTime = uint32(block.timestamp);
        operatorToPaymentChallenge[operator] = challengeContract;
        emit PaymentChallengeInit(operator, msg.sender);
    }

    function resolvePaymentChallenge(address operator, bool winner) external {
        require(
            msg.sender == operatorToPaymentChallenge[operator],
            "Only the payment challenge contract can call"
        );
        if (winner) {
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

    function getDumpNumberFee(uint48 _dumpNumber)
        public
        view
        returns (uint256)
    {
        return dumpNumberToFee[_dumpNumber];
    }

    function getDumpNumberSignatureHash(uint48 _dumpNumber)
        public
        view
        returns (bytes32)
    {
        return dumpNumberToSignatureHash[_dumpNumber];
    }

    function getPaymentCollateral(address operator)
        public
        view
        returns (uint256)
    {
        return operatorToPayment[operator].collateral;
    }

    function getDepositRoot(uint256 blockNumber) public view returns(bytes32) {
        return depositRoots[blockNumber];
    }

    function payFee(address) external payable {
        revert();
    }

    function onResponse(
        bytes32 queryHash,
        address operator,
        bytes32 reponseHash,
        uint256 senderWeight
    ) external {}

    function setFeePerBytePerTime(uint256 _feePerBytePerTime)
        public
        onlyQMGovernance
    {
        feePerBytePerTime = _feePerBytePerTime;
    }

    function setPaymentFraudProofCollateral(
        uint256 _paymentFraudProofCollateral
    ) public onlyQMGovernance {
        paymentFraudProofCollateral = _paymentFraudProofCollateral;
    }

    function setDataLayr(IDataLayr _dataLayr) public {
        require(
            (address(dataLayr) == address(0)) || (queryManager.timelock() == msg.sender),
            "Query Manager governance can only call this function, or DL must not be initialized"
        );
        dataLayr = _dataLayr;
    }

    /* function removed for now since it tries to modify an immutable variable
    function setPaymentToken(
        IERC20 _paymentToken
    ) public onlyQMGovernance {
        paymentToken = _paymentToken;
    }
*/
}
