// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IRepository.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/IProofOfStakingOracle.sol";
import "../../interfaces/IDelegationTerms.sol";
import "./DataLayrServiceManagerStorage.sol";
import "./DataLayrDisclosureChallengeFactory.sol";
import "./DataLayrSignatureChecker.sol";
import "../../libraries/BytesLib.sol";
import "../../libraries/Merkle.sol";
import "../Repository.sol";
import "./DataLayrDisclosureUtils.sol";
import "./DataLayrLowDegreeChallenge.sol";
import "ds-test/test.sol";

/**
 * @notice This contract is used for:
            - initializing the data store by the disperser
            - confirming the data store by the disperser with inferred aggregated signatures of the quorum
            - doing forced disclosure challenge
            - doing payment challenge
 */
contract DataLayrServiceManager is
    DataLayrSignatureChecker,
    IProofOfStakingOracle
    // ,DSTest
{
    using BytesLib for bytes;
    //TODO: mechanism to change any of these values?
    uint32 internal constant MIN_STORE_SIZE = 32;
    uint32 internal constant MAX_STORE_SIZE = 4e9;
    uint32 internal constant MIN_STORE_LENGTH = 60;
    uint32 internal constant MAX_STORE_LENGTH = 604800;
    // only repositoryGovernance can call this, but 'sender' called instead
    error OnlyRepositoryGovernance(
        address repositoryGovernance,
        address sender
    );
    // proposed data store size is too small. minimum size is 'minStoreSize' in bytes, but 'proposedSize' is smaller
    error StoreTooSmall(uint256 minStoreSize, uint256 proposedSize);
    // proposed data store size is too large. maximum size is 'maxStoreSize' in bytes, but 'proposedSize' is larger
    error StoreTooLarge(uint256 maxStoreSize, uint256 proposedSize);
    // proposed data store length is too large. minimum length is 'minStoreLength' in bytes, but 'proposedLength' is shorter
    error StoreTooShort(uint256 minStoreLength, uint256 proposedLength);
    // proposed data store length is too large. maximum length is 'maxStoreLength' in bytes, but 'proposedLength' is longer
    error StoreTooLong(uint256 maxStoreLength, uint256 proposedLength);

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
     * @notice factory contract used to deploy new DataLayrPaymentChallenge contracts
     */
    DataLayrPaymentChallengeFactory
        public immutable dataLayrPaymentChallengeFactory;

    /**
     * @notice factory contract used to deploy new DataLayrDisclosureChallenge contracts
     */
    DataLayrDisclosureChallengeFactory
        public immutable dataLayrDisclosureChallengeFactory;

    DataLayrDisclosureUtils public immutable disclosureUtils;

    DataLayrLowDegreeChallenge public dataLayrLowDegreeChallenge;

    // EVENTS
    /**
     @notice used for notifying that disperser has initiated a forced disclosure challenge.
     */
    event DisclosureChallengeInit(bytes32 headerHash, address operator);

    /**
     @notice used for disclosing the multireveals and coefficients of the associated interpolating polynomial
     */
    event DisclosureChallengeResponse(
        bytes32 headerHash,
        address operator,
        bytes poly
    );

    /**
     @notice used while initializing the interactive forced disclosure
     */
    event DisclosureChallengeInteractive(
        bytes32 headerHash,
        address disclosureChallenge,
        address operator
    );

    event PaymentCommit(
        address operator,
        uint32 fromDumpNumber,
        uint32 toDumpNumber,
        uint256 fee
    );

    event PaymentChallengeInit(address operator, address challenger);

    event PaymentChallengeResolution(address operator, bool operatorWon);

    event PaymentRedemption(address operator, uint256 fee);

    event LowDegreeChallengeResolution(
        bytes32 headerHash,
        address operator,
        bool operatorWon
    );

    constructor(
        IEigenLayrDelegation _eigenLayrDelegation,
        IERC20 _paymentToken,
        IERC20 _collateralToken,
        uint256 _feePerBytePerTime,
        DataLayrPaymentChallengeFactory _dataLayrPaymentChallengeFactory,
        DataLayrDisclosureChallengeFactory _dataLayrDisclosureChallengeFactory,
        DataLayrDisclosureUtils _disclosureUtils
    ) DataLayrServiceManagerStorage(_paymentToken, _collateralToken) {
        eigenLayrDelegation = _eigenLayrDelegation;
        feePerBytePerTime = _feePerBytePerTime;
        dataLayrPaymentChallengeFactory = _dataLayrPaymentChallengeFactory;
        dataLayrDisclosureChallengeFactory = _dataLayrDisclosureChallengeFactory;
        disclosureUtils = _disclosureUtils;
    }



    modifier onlyRepositoryGovernance() {
        if (!(address(repository.owner()) == msg.sender)) {
            revert OnlyRepositoryGovernance(address(repository.owner()), msg.sender);
        }
        _;
    }

    function setRepository(IRepository _repository) public {
        require(address(repository) == address(0), "repository already set");
        repository = _repository;
    }

    function setLowDegreeChallenge(DataLayrLowDegreeChallenge _dataLayrLowDegreeChallenge) public {
        dataLayrLowDegreeChallenge = _dataLayrLowDegreeChallenge;
    }


    /**
     * @notice This function is used for
     *          - notifying in the settlement layer that the disperser has asserted the data
     *            into DataLayr and is waiting for obtaining quorum of DataLayr operators to sign,
     *          - asserting the metadata corresponding to the data asserted into DataLayr
     *          - escrow the service fees that DataLayr operators will receive from the disperser
     *            on account of their service.
     */
    /**
     * @param header is the summary of the data that is being asserted into DataLayr,
     * @param storePeriodLength for which the data has to be stored by the DataLayr operators,
     * @param totalBytes  is the size of the data ,
     * @param storePeriodLength is time in seconds for which the data has to be stored by the DataLayr nodes, 
     * @param blockNumber for which the confirmation will consult total + operator stake amounts 
     *          -- must not be more than 'BLOCK_STALE_MEASURE' (defined in DataLayr) blocks in past
     */
    function initDataStore(
        bytes calldata header,
        uint32 totalBytes,
        uint32 storePeriodLength,
        uint32 blockNumber
    ) external payable {
        bytes32 headerHash = keccak256(header);

        if (totalBytes < MIN_STORE_SIZE) {
            revert StoreTooSmall(MIN_STORE_SIZE, totalBytes);
        }
        if (totalBytes > MAX_STORE_SIZE) {
            revert StoreTooLarge(MAX_STORE_SIZE, totalBytes);
        }
        if (storePeriodLength <= MIN_STORE_LENGTH) {
            revert StoreTooShort(MIN_STORE_LENGTH, storePeriodLength);
        }
        if (storePeriodLength >= MAX_STORE_LENGTH) {
            revert StoreTooLong(MAX_STORE_LENGTH, storePeriodLength);
        }

        // evaluate the total service fees that msg.sender has to put in escrow for paying out
        // the DataLayr nodes for their service
        uint256 fee = (totalBytes * feePerBytePerTime) * storePeriodLength;

        // record the total service fee that will be paid out for this assertion of data
        dumpNumberToFee[dumpNumber] = fee;

        // recording the expiry time until which the DataLayr operators, who sign up to
        // part of the quorum, have to store the data
        IDataLayrRegistry(address(repository.voteWeigher())).setLatestTime(
            uint32(block.timestamp) + storePeriodLength
        );

        // escrow the total service fees from the disperser to the DataLayr operators in this contract
        paymentToken.transferFrom(msg.sender, address(this), fee);

        // call DataLayr contract
        dataLayr.initDataStore(
            dumpNumber,
            headerHash,
            totalBytes,
            storePeriodLength,
            blockNumber,
            header
        );

        // increment the counter
        ++dumpNumber;
    }

    /**
     * @notice This function is used for
     *          - disperser to notify that signatures on the message, comprising of hash( headerHash ),
     *            from quorum of DataLayr nodes have been obtained,
     *          - check that each of the signatures are valid,
     *          - call the DataLayr contract to check that whether quorum has been achieved or not.
     */
    /** 
     @param data is of the format:
            <
             bytes32 headerHash,
             uint48 index of the totalStake corresponding to the dumpNumber in the 'totalStakeHistory' array of the DataLayrRegistry
             uint32 numberOfNonSigners,
             uint256[numberOfSigners][4] pubkeys of nonsigners,
             uint32 apkIndex,
             uint256[4] apk,
             uint256[2] sigma
            >
     */
    // CRITIC: there is an important todo in this function
    function confirmDataStore(bytes calldata data) external payable {
        // verify the signatures that disperser is claiming to be that of DataLayr operators
        // who have agreed to be in the quorum
        (
            uint32 dumpNumberToConfirm,
            bytes32 headerHash,
            SignatoryTotals memory signedTotals,
            bytes32 signatoryRecordHash
        ) = checkSignatures(data);

        require(dumpNumberToConfirm > 0 && dumpNumberToConfirm < dumpNumber, "Dump number is invalid");

        /**
         * @notice checks that there is no need for posting a deposit root required for proving
         * the new staking of ETH into Ethereum.
         */
        /**
         @dev for more details, see "depositPOSProof" in EigenLayrDeposit.sol.
         */
        require(
            dumpNumberToConfirm % depositRootInterval != 0,
            "Must post a deposit root now"
        );

        // record the compressed information pertaining to this particular dump
        /**
         @notice signatoryRecordHash records pubkey hashes of DataLayr operators who didn't sign
         */
        dumpNumberToSignatureHash[dumpNumberToConfirm] = signatoryRecordHash;

        // call DataLayr contract to check whether quorum is satisfied or not and record it
        dataLayr.confirm(
            dumpNumberToConfirm,
            headerHash,
            signedTotals.ethStakeSigned,
            signedTotals.eigenStakeSigned,
            signedTotals.totalEthStake,
            signedTotals.totalEigenStake
        );
    }

    /**
     * @notice This function is used when the  DataLayr is used to update the POSt hash
     *         along with the regular assertion of data into the DataLayr by the disperser. This
     *         function enables
     *          - disperser to notify that signatures, comprising of hash(depositRoot || headerHash),
     *            from quorum of DataLayr nodes have been obtained,
     *          - check that each of the signatures are valid,
     *          - store the POSt hash, given by depositRoot,
     *          - call the DataLayr contract to check  whether quorum has been achieved or not.
     */
    function confirmDataStoreWithPOSt(
        bytes32 depositRoot,
        bytes32 headerHash,
        bytes calldata data
    ) external payable {
        // verify the signatures that disperser is claiming to be that of DataLayr operators
        // who have agreed to be in the quorum
        (
            uint32 dumpNumberToConfirm,
            bytes32 depositFerkleHash,
            SignatoryTotals memory signedTotals,
            bytes32 signatoryRecordHash
        ) = checkSignatures(data);

        /**
          @notice checks that there is need for posting a deposit root required for proving
          the new staking of ETH into Ethereum. 
         */
        /**
          @dev for more details, see "depositPOSProof" in EigenLayrDeposit.sol.
         */
        require(
            dumpNumberToConfirm % depositRootInterval == 0,
            "Shouldn't post a deposit root now"
        );

        // record the compressed information on all the DataLayr nodes who signed
        /**
         @notice signatoryRecordHash records pubkey hashes of DataLayr operators who didn't sign
         */
        dumpNumberToSignatureHash[dumpNumberToConfirm] = signatoryRecordHash;

        /**
         * when posting a deposit root, DataLayr nodes will sign hash(depositRoot || headerHash)
         * instead of the usual headerHash, so the submitter must specify the preimage
         */
        require(
            keccak256(abi.encodePacked(depositRoot, headerHash)) ==
                depositFerkleHash,
            "Ferkle or deposit root is incorrect"
        );

        // record the deposit root (POSt hash)
        depositRoots[block.number] = depositRoot;

        // call DataLayr contract to check whether quorum is satisfied or not and record it
        dataLayr.confirm(
            dumpNumberToConfirm,
            headerHash,
            signedTotals.ethStakeSigned,
            signedTotals.eigenStakeSigned,
            signedTotals.totalEthStake,
            signedTotals.totalEigenStake
        );
    }

    /**
     @notice This is used by a DataLayr operator to make claim on the @param amount that they deserve 
             for their service since their last payment until @param toDumpNumber  
     **/
    function commitPayment(uint32 toDumpNumber, uint120 amount) external {
        IDataLayrRegistry dlRegistry = IDataLayrRegistry(
            address(repository.voteWeigher())
        );

        // only registered DataLayr operators can call
        require(
            dlRegistry.getOperatorType(msg.sender) != 0,
            "Only registered operators can call this function"
        );

        require(toDumpNumber <= dumpNumber, "Cannot claim future payments");

        // operator puts up collateral which can be slashed in case of wrongful payment claim
        collateralToken.transferFrom(
            msg.sender,
            address(this),
            paymentFraudProofCollateral
        );

        /**
         @notice recording payment claims for the DataLayr operators
         */
        uint32 fromDumpNumber;

        // for the special case of this being the first payment that is being claimed by the DataLayr operator;
        /**
         @notice this special case also implies that the DataLayr operator must be claiming payment from 
                 when the operator registered.   
         */
        if (operatorToPayment[msg.sender].fromDumpNumber == 0) {
            // get the dumpNumber when the DataLayr operator registered
            fromDumpNumber = dlRegistry.getOperatorFromDumpNumber(msg.sender);

            require(fromDumpNumber < toDumpNumber, "invalid payment range");

            // record the payment information pertaining to the operator
            operatorToPayment[msg.sender] = Payment(
                fromDumpNumber,
                toDumpNumber,
                uint32(block.timestamp),
                amount,
                // setting to 0 to indicate commitment to payment claim
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

    /**
     @notice This function can only be called after the challenge window for the payment claim has completed.
     */
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

        ///look up payment amount and delegation terms address for the msg.sender
        uint256 amount = operatorToPayment[msg.sender].amount;
        IDelegationTerms dt = eigenLayrDelegation.delegationTerms(msg.sender);

        // i.e. if operator is not a 'self operator'
        if (address(dt) != address(0)) {
            // transfer the amount due in the payment claim of the operator to its delegation
            // terms contract, where the delegators can withdraw their rewards.
            paymentToken.transfer(address(dt), amount);

            // inform the DelegationTerms contract of the payment, which would determine
            // the rewards operator and its delegators are eligible for
            dt.payForService(paymentToken, amount);

            // i.e. if the operator *is* a 'self operator'
        } else {
            //simply transfer the payment amount in this case
            paymentToken.transfer(msg.sender, amount);
        }

        emit PaymentRedemption(msg.sender, amount);
    }

    //
    //TODO: How much collateral
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
            block.timestamp <
                operatorToPayment[operator].commitTime +
                    paymentFraudProofInterval &&
                operatorToPayment[operator].status == 0,
            "Fraud proof interval has passed"
        );

        // deploy new challenge contract
        address challengeContract = dataLayrPaymentChallengeFactory
            .createDataLayrPaymentChallenge(
                operator,
                msg.sender,
                address(this),
                operatorToPayment[operator].fromDumpNumber,
                operatorToPayment[operator].toDumpNumber,
                amount1,
                amount2
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

    function resolveLowDegreeChallenge(bytes32 headerHash, address operator, uint32 commitTime) public {
        require(msg.sender == address(dataLayrLowDegreeChallenge), "Only low degree resolver can resolve low degree challenges");
        require(commitTime != 0, "Low degree challenge does not exist");
        if(commitTime == 1) {
            //pay operator
            emit LowDegreeChallengeResolution(headerHash, operator, true);
        } else if (block.timestamp - commitTime > lowDegreeFraudProofInterval) {
            //pay challenger
            emit LowDegreeChallengeResolution(headerHash, operator, false);
        } else {
            revert("Low degree challenge not resolvable");
        }
    }

    /**
     @notice This function is used for opening a forced disclosure challenge against a particular 
             DataLayr operator for a particular dump number.
     */
    /**
     @param headerHash is the hash of summary of the data that was asserted into DataLayr by the disperser during call to initDataStore,
     @param operator is the DataLayr operator against whom forced disclosure challenge is being opened
     @param nonSignerIndex is used for verifying that DataLayr operator is member of the quorum that signed on the dump
     param nonSignerPubkeyHashes is the array of hashes of pubkey of all DataLayr operators that didn't sign for the dump
     param totalEthStakeSigned is the total ETH that has been staked with the DataLayr operators that are in quorum
     param totalEigenStakeSigned is the total Eigen that has been staked with the DataLayr operators that are in quorum
     */
    function forceOperatorToDisclose(
        bytes32 headerHash,
        address operator,
        uint32 operatorIndex,
        uint32 totalOperatorsIndex,
        uint256 nonSignerIndex,
        SignatoryRecordMinusDumpNumber calldata signatoryRecord
    ) public {
        IDataLayrRegistry dlRegistry = IDataLayrRegistry(
            address(repository.registrationManager())
        );
        uint32 chunkNumber;
        uint32 expireTime;

        {
            /**
            Get information on the dataStore for which disperser is being challenged. This dataStore was 
            constructed during call to initDataStore in DataLayr.sol by the disperser.
            */
            (
                uint32 dumpNumber,
                uint32 initTime,
                uint32 storePeriodLength,
                ,
                bool committed
            ) = dataLayr.dataStores(headerHash);

            expireTime = initTime + storePeriodLength;

            // check that disperser had acquire quorum for this dataStore
            require(committed, "Dump is not committed yet");

            /** 
            Check that the information supplied as input for forced disclosure for this particular data 
            dump on DataLayr is correct
            */
            require(
                getDumpNumberSignatureHash(dumpNumber) ==
                    keccak256(
                        abi.encodePacked(
                            dumpNumber,
                            signatoryRecord.nonSignerPubkeyHashes,
                            signatoryRecord.totalEthStakeSigned,
                            signatoryRecord.totalEigenStakeSigned
                        )
                    ),
                "Sig record does not match hash"
            );

            operatorIndex = dlRegistry.getOperatorIndex(
                operator,
                dumpNumber,
                operatorIndex
            );
            totalOperatorsIndex = dlRegistry.getTotalOperators(
                dumpNumber,
                totalOperatorsIndex
            );
            chunkNumber = (operatorIndex + dumpNumber) % totalOperatorsIndex;
        }

        /** 
          @notice Check that the DataLayr operator against whom forced disclosure is being initiated, was
                  actually part of the quorum for the @param dumpNumber.
          
                  The burden of responsibility lies with the challenger to show that the DataLayr operator 
                  is not part of the non-signers for the dump. Towards that end, challenger provides
                  @param index such that if the relationship among nonSignerPubkeyHashes (nspkh) is:
                   uint256(nspkh[0]) <uint256(nspkh[1]) < ...< uint256(nspkh[index])< uint256(nspkh[index+1]),...
                  then,
                        uint256(nspkh[index]) <  uint256(operatorPubkeyHash) < uint256(nspkh[index+1])
         */
        /**
          @dev checkSignatures in DataLayrSignaturechecker.sol enforces the invariant that hash of 
               non-signers pubkey is recorded in the compressed signatory record in an  ascending
               manner.      
        */

        {
            if (signatoryRecord.nonSignerPubkeyHashes.length != 0) {
                // get the pubkey hash of the DataLayr operator
                bytes32 operatorPubkeyHash = dlRegistry.getOperatorPubkeyHash(
                    operator
                );
                //not super critic: new call here, maybe change comment
                disclosureUtils.checkInclusionExclusionInNonSigner(
                    operatorPubkeyHash,
                    nonSignerIndex,
                    signatoryRecord
                );
            }
        }

        /**
         @notice check that the challenger is giving enough time to the DataLayr operator for responding to
                 forced disclosure. 
         */
        // todo: need to finalize this.

        /*
        require(
            block.timestamp < expireTime - 600 ||
                (block.timestamp <
                    disclosureForOperator[headerHash][operator].commitTime +
                        2 *
                        disclosureFraudProofInterval &&
                    block.timestamp >
                    disclosureForOperator[headerHash][operator].commitTime +
                        disclosureFraudProofInterval),
            "Must challenge before 10 minutes before expiry or within consecutive disclosure time"
        );
        */

        // check that the DataLayr operator hasn't been challenged yet
        require(
            disclosureForOperator[headerHash][operator].status == 0,
            "Operator is already challenged for dump number"
        );

        // record details of forced disclosure challenge that has been opened
        disclosureForOperator[headerHash][operator] = DisclosureChallenge(
            // the current timestamp when the challenge was created
            uint32(block.timestamp),
            // challenger's address
            msg.sender,
            // address of challenge contract if there is one
            address(0),
            // todo: set degree here
            0,
            // set the status to 1 as forced disclosure challenge has been opened
            1,
            0,
            0,
            bytes32(0),
            chunkNumber,
            0
        );

        emit DisclosureChallengeInit(headerHash, operator);
    }

    /**
     @notice 
            Consider C(x) to be the polynomial that was used by the disperser to obtain the symbols in coded 
            chunks that was dispersed among the DataLayr operators. Let phi be an l-th root of unity, that is,
            phi^l = 1. Then, assuming each DataLayr operator has deposited same stake, 
            for the DataLayr operator k, it will receive the following symbols from the disperser:

                        C(w^k), C(w^k * phi), C(w^k * phi^2), ..., C(w^k * phi^(l-1))

            The disperser will also compute an interpolating polynomial for the DataLayr operator k that passes 
            through the above l points. Denote this interpolating polynomial by I_k(x). The disperser also 
            sends the coefficients of this interpolating polynomial I_k(x) to the DataLayr operator k. Note that
            disperser had already committed to C(s) during initDataStore, where s is the SRS generated at some
            initiation ceremony whose corresponding secret key is unknown.
            
            Observe that 

               (C - I_k)(w^k) =  (C - I)(w^k * phi) = (C - I)(w^k * phi^2) = ... = (C - I)(w^k * phi^(l-1)) = 0

            Therefore, w^k, w^k * phi, w^k * phi^2, ..., w^k * phi^l are the roots of the polynomial (C - I_k)(x).
            Therefore, one can write:

                (C - I_k)(x) = [(x - w^k) * (x - w^k * phi) * (x - w^k * phi^2) * ... * (x - w^k * phi^(l-1))] * Pi(x)
                           = [x^l - (w^k)^l] * Pi(x)

            where x^l - (w^k)^l is the zero polynomial. Let us denote the zero poly by Z_k(x) = x^l - (w^k)^l.
            
            Now, under forced disclosure, DataLayr operator k needs to just reveal the coefficients of the 
            interpolating polynomial I_k(x). The challenger for the forced disclosure can use this polynomial 
            I_k(x) to reconstruct the symbols that are stored with the DataLayr operator k which is given by:

                        I_k(w^k), I_k(w^k * phi), I_k(w^k * phi^2), ..., I_k(w^k * phi^(l-1))

            However, revealing the coefficients of I_k(x) gives no guarantee that these coefficints are correct. 
            So, we in order to respond to the forced disclosure challenge:
              (1) DataLayr operator first has to disclose proof (quotient polynomial) Pi(s) and commitment to 
                  zero polynomial Z_k(x) in order to help on-chain code to certify the commitment to the 
                  interpolating polynomial I_k(x),   
              (2) reveal the coefficients of the interpolating polynomial I_k(x) 
     */

    /**
     @notice This function is used by the DataLayr operator to respond to the forced disclosure challenge.   
     */
    /**
     @param multireveal comprises of both Pi(s) and I_k(s) in the format: [Pi(s).x, Pi(s).y, I_k(s).x, I_k(s).y]
     @param poly are the coefficients of the interpolating polynomial I_k(x)
     @param zeroPoly is the commitment to the zero polynomial x^l - (w^k)^l on group G2. The format is:
                     [Z_k(s).x0, Z_k(s).x1, Z_k(s).y0, Z_k(s).y1].    
     @param zeroPolyProof is the Merkle proof for membership of @param zeroPoly in Merkle tree
     @param header is the summary of the data that was asserted into DataLayr by the disperser during call to initDataStore,
     */
    function respondToDisclosureInit(
        bytes calldata header,
        uint256[4] calldata multireveal,
        bytes calldata poly,
        uint256[4] memory zeroPoly,
        bytes calldata zeroPolyProof
    ) external {
        bytes32 headerHash = keccak256(header);

        // check that DataLayr operator is responding to the forced disclosure challenge period within some window
        /*
        require(
            block.timestamp <
                disclosureForOperator[headerHash][msg.sender].commitTime +
                    disclosureFraudProofInterval,
            "must be in fraud proof period"
        );
        */
        bytes32 data;
        uint256 position;
        // check that it is DataLayr operator who is supposed to respond
        require(
            disclosureForOperator[headerHash][msg.sender].status == 1,
            "Not in operator initial response phase"
        );

        //not so critic: move comments here
        uint48 degree = disclosureUtils.validateDisclosureResponse(
            disclosureForOperator[headerHash][msg.sender].chunkNumber,
            header,
            multireveal,
            zeroPoly,
            zeroPolyProof
        );

        /*
        degree is the poly length, no need to multiply 32, as it is the size of data in bytes
        require(
            (degree + 1) * 32 == poly.length,
            "Polynomial must have a 256 bit coefficient for each term"
        );
        */

        // check that [zeroPoly.x0, zeroPoly.x1, zeroPoly.y0, zeroPoly.y1] is actually the "chunkNumber" leaf
        // of the zero polynomial Merkle tree

        // update disclosure to record Interpolating poly commitment - [I(s).x, Is(s).y]
        disclosureForOperator[headerHash][msg.sender].x = multireveal[2];
        disclosureForOperator[headerHash][msg.sender].y = multireveal[3];

        // update disclosure to record  hash of interpolating polynomial I_k(x)
        disclosureForOperator[headerHash][msg.sender].polyHash = keccak256(
            poly
        );

        // update disclosure to record degree of the interpolating polynomial I_k(x)
        disclosureForOperator[headerHash][msg.sender].degree = degree;
        disclosureForOperator[headerHash][msg.sender].status = 2;

        emit DisclosureChallengeResponse(headerHash, msg.sender, poly);
    }

    /**
     @notice 
        For simpicity of notation, let the interpolating polynomial I_k(x) for the DataLayr operation k
        be denoted by I(x). Assume the interpolating polynomial is of degree d and its coefficients are 
        c_0, c_1, ...., c_d. 
        
        Then, substituting x = s, we can write:
         I(s) = c_0 + c_1 * s + c_2 * s^2 + c_3 * s^3 + ... + c_d * s^d
              = [c_0 + c_1 * s + ... + c_{d/2} * s^(d/2)] + [c_{d/2 + 1} * s^(d/2 + 1) ... + c_d * s^d]
              =                   coors1(s)               +                        coors2(s)
     */
    /**
     @param headerHash is the hash of summary of the data that was asserted into DataLayr by the disperser during call to initDataStore,
     @param operator is the address of the DataLayr operator
     @param coors this is of the format: [coors1(s).x, coors1(s).y, coors2(s).x, coors2(s).y]
     */
    function initInterpolatingPolynomialFraudProof(
        bytes32 headerHash,
        address operator,
        uint256[4] memory coors
    ) public {
        require(
            disclosureForOperator[headerHash][operator].challenger ==
                msg.sender,
            "Only challenger can call"
        );

        require(
            disclosureForOperator[headerHash][operator].status == 2,
            "Not in post operator response phase"
        );

        // update commit time
        disclosureForOperator[headerHash][operator].commitTime = uint32(
            block.timestamp
        );

        // update status to challenged
        disclosureForOperator[headerHash][operator].status = 3;

        /**
         @notice We need to ensure that the challenge is legitimate. In order to do so, we want coors1(s) and 
                 coors2(s) to be such that:
                                        I(s) != coors1(s) + coors2(s)   
         */
        uint256[2] memory res;

        // doing coors1(s) + coors2(s)
        assembly {
            if iszero(call(not(0), 0x06, 0, coors, 0x80, res, 0x40)) {
                revert(0, 0)
            }
        }

        // checking I(s) != coors1(s) + coors2(s)
        require(
            res[0] != disclosureForOperator[headerHash][operator].x ||
                res[0] != disclosureForOperator[headerHash][operator].y,
            "Cannot commit to same polynomial as the interpolating polynomial"
        );

        // degree has been narrowed down by half every dissection
        uint48 halfDegree = disclosureForOperator[headerHash][operator].degree /
            2;

        // initializing the interaction-style forced disclosure challenge
        address disclosureChallenge = address(
            dataLayrDisclosureChallengeFactory
                .createDataLayrDisclosureChallenge(
                    headerHash,
                    operator,
                    msg.sender,
                    coors[0],
                    coors[1],
                    coors[2],
                    coors[3],
                    halfDegree
                )
        );

        // recording the contract address for interaction-style forced disclosure challenge
        disclosureForOperator[headerHash][operator]
            .challenge = disclosureChallenge;

        emit DisclosureChallengeInteractive(
            headerHash,
            disclosureChallenge,
            operator
        );
    }
    
    /**
     @notice This function is called for settling the forced disclosure challenge.
     */
    /**
     @param headerHash is the hash of summary of the data that was asserted into DataLayr by the disperser during call to initDataStore,
     @param operator is the address of DataLAyr operator
     @param winner representing who is the winner - challenged DataLayr operator or the challenger?  
     */
    // CRITIC: there are some @todo's here
    function resolveDisclosureChallenge(
        bytes32 headerHash,
        address operator,
        bool winner
    ) external {
        if (
            msg.sender == disclosureForOperator[headerHash][operator].challenge
        ) {
            /** 
                the above condition would be called by the forced disclosure challenge contract when the final 
                step of the interactive fraudproof for single monomial has finished
            */
            if (winner) {
                // challenger was wrong, allow for another forced disclosure challenge
                disclosureForOperator[headerHash][operator].status = 0;
                operatorToPayment[operator].commitTime = uint32(
                    block.timestamp
                );

                // @todo give them previous challengers payment
            } else {
                // challeger was correct, reset payment
                disclosureForOperator[headerHash][operator].status = 4;
                // @todo do something
            }
        } else if (
            msg.sender == disclosureForOperator[headerHash][operator].challenger
        ) {
            /** 
                the above condition would be called by the challenger in case if the DataLayr operator doesn't 
                respond in time
             */

            require(
                disclosureForOperator[headerHash][operator].status == 1,
                "Operator is not in initial response phase"
            );
            require(
                block.timestamp >
                    disclosureForOperator[headerHash][operator].commitTime +
                        disclosureFraudProofInterval,
                "Fraud proof period has not passed"
            );

            //slash here
        } else if (msg.sender == operator) {
            /** 
                the above condition would be called by the DataLayr operator in case if the challenger doesn't 
                respond in time
             */

            require(
                disclosureForOperator[headerHash][operator].status == 2,
                "Challenger is not in commitment challenge phase"
            );
            require(
                block.timestamp >
                    disclosureForOperator[headerHash][operator].commitTime +
                        disclosureFraudProofInterval,
                "Fraud proof period has not passed"
            );

            //get challengers payment here
        } else {
            revert(
                "Only the challenge contract, challenger, or operator can call"
            );
        }
    }

    /**
     @notice this function returns the compressed record on the signatures of DataLayr nodes 
             that aren't part of the quorum for this @param _dumpNumber.
     */
    function getDumpNumberSignatureHash(uint32 _dumpNumber)
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

    function getDepositRoot(uint256 blockNumber) public view returns (bytes32) {
        return depositRoots[blockNumber];
    }

    function getPolyHash(address operator, bytes32 headerHash)
        public
        view
        returns (bytes32)
    {
        return disclosureForOperator[headerHash][operator].polyHash;
    }

    function setFeePerBytePerTime(uint256 _feePerBytePerTime)
        public
        onlyRepositoryGovernance
    {
        feePerBytePerTime = _feePerBytePerTime;
    }

    function setPaymentFraudProofCollateral(
        uint256 _paymentFraudProofCollateral
    ) public onlyRepositoryGovernance {
        paymentFraudProofCollateral = _paymentFraudProofCollateral;
    }

    function setDataLayr(IDataLayr _dataLayr) public {
        require(
            (address(dataLayr) == address(0)) ||
                (address(repository.owner()) == msg.sender),
            "only repository governance can call this function, or DL must not be initialized"
        );
        dataLayr = _dataLayr;
    }

    /// @notice returns the time when the serviceObject, associated with serviceObjectHash, was created
    function getServiceObjectCreationTime(bytes32 serviceObjectHash)
        public
        view
        returns (uint256)
    {
        (, uint32 initTime, , , ) = dataLayr.dataStores(serviceObjectHash);
        uint256 timeCreated = uint256(initTime);
        if (timeCreated != 0) {
            return timeCreated;
        } else {
            return type(uint256).max;
        }
    }

    /// @notice returns the time when the serviceObject, associated with serviceObjectHash, will expire
    function getServiceObjectExpiry(bytes32 serviceObjectHash)
        external
        view
        returns (uint256)
    {
        (, uint32 initTime, uint32 storePeriodLength, , ) = dataLayr.dataStores(
            serviceObjectHash
        );
        uint256 timeCreated = uint256(initTime);
        if (timeCreated != 0) {
            return (timeCreated + storePeriodLength);
        } else {
            return type(uint256).max;
        }
    }

    /* function removed for now since it tries to modify an immutable variable
    function setPaymentToken(
        IERC20 _paymentToken
    ) public onlyRepositoryGovernance {
        paymentToken = _paymentToken;
    }
*/
}
