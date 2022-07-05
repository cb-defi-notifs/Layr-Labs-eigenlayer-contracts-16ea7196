// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IRepository.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/IProofOfStakingOracle.sol";
import "../../interfaces/IDelegationTerms.sol";
import "./DataLayrServiceManagerStorage.sol";
import "./DataLayrSignatureChecker.sol";
import "../../libraries/BytesLib.sol";
import "../../libraries/Merkle.sol";
import "../Repository.sol";
import "./DataLayrChallengeUtils.sol";
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
    DataLayrPaymentChallengeFactory public immutable dataLayrPaymentChallengeFactory;


    DataLayrLowDegreeChallenge public dataLayrLowDegreeChallenge;

    // EVENTS
    event PaymentCommit(
        address operator,
        uint32 fromDataStoreId,
        uint32 toDataStoreId,
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

    DataStoresForDuration public dataStoresForDuration;

    constructor(
        IEigenLayrDelegation _eigenLayrDelegation,
        IERC20 _paymentToken,
        IERC20 _collateralToken,
        uint256 _feePerBytePerTime,
        DataLayrPaymentChallengeFactory _dataLayrPaymentChallengeFactory
    ) DataLayrServiceManagerStorage(_paymentToken, _collateralToken) {
        eigenLayrDelegation = _eigenLayrDelegation;
        feePerBytePerTime = _feePerBytePerTime;
        dataLayrPaymentChallengeFactory = _dataLayrPaymentChallengeFactory;
        dataStoresForDuration.dataStoreId = 1;
        
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

    function depositFutureFees(address onBehalfOf, uint256 amount) external {
        paymentToken.transferFrom(msg.sender, address(this), amount);
        depositsOf[onBehalfOf] += amount;
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
     * @param duration for which the data has to be stored by the DataLayr operators, scaled down by DURATION_SCALE,
     * @param totalBytes  is the size of the data ,
     * @param blockNumber for which the confirmation will consult total + operator stake amounts 
     *          -- must not be more than 'BLOCK_STALE_MEASURE' (defined in DataLayr) blocks in past
     */
    function initDataStore(
        bytes calldata header,
        uint8 duration,
        uint32 totalBytes,
        uint32 blockNumber
    ) external payable {
        bytes32 headerHash = keccak256(header);

        if (totalBytes < MIN_STORE_SIZE) {
            revert StoreTooSmall(MIN_STORE_SIZE, totalBytes);
        }
        if (totalBytes > MAX_STORE_SIZE) {
            revert StoreTooLarge(MAX_STORE_SIZE, totalBytes);
        }
        require(duration >= 1 && duration <= MAX_DATASTORE_DURATION, "Invalid duration");
        
        uint32 storePeriodLength = uint32(duration * DURATION_SCALE);

        // evaluate the total service fees that msg.sender has to put in escrow for paying out
        // the DataLayr nodes for their service
        uint256 fee = (totalBytes * feePerBytePerTime) * storePeriodLength;

        // require that disperser has sent enough fees to this contract to pay for this datastore
        // this will revert if the deposits are not high enough due to undeflow
        uint g = gasleft();

        depositsOf[msg.sender] -= fee;
        
        //emit log_named_uint("1", g - gasleft());

        //increment totalDataStoresForDuration and append it to the list of datastores stored at this timestamp
        dataStoreIdsForDuration[duration][block.timestamp] =
                keccak256(
                    abi.encodePacked(
                        dataStoreIdsForDuration[duration][block.timestamp], 
                        getDataStoresForDuration(duration) + 1,
                        dataStoresForDuration.dataStoreId,
                        uint96(fee)
                    )
                );


        
        // call DataLayr contract
        g = gasleft();
        dataLayr.initDataStore(
            dataStoresForDuration.dataStoreId,
            headerHash,
            totalBytes,
            storePeriodLength,
            blockNumber,
            header
        );

        //emit log_named_uint("3", g - gasleft());

        /**
        @notice sets the latest time until which any of the active DataLayr operators that haven't committed
                yet to deregistration are supposed to serve.
        */
        // recording the expiry time until which the DataLayr operators, who sign up to
        // part of the quorum, have to store the data
        
        uint32 _latestTime = uint32(block.timestamp) + storePeriodLength;

        g = gasleft();
        if (_latestTime > latestTime) {
            dataStoresForDuration.latestTime = _latestTime;            
        }

        incrementDataStoresForDuration(duration);
        
        // increment the counter
        ++dataStoresForDuration.dataStoreId;
        //emit log_named_uint("4", g - gasleft()); 
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
             uint48 index of the totalStake corresponding to the dataStoreId in the 'totalStakeHistory' array of the DataLayrRegistry
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
        uint g = gasleft();
        (
            uint32 dataStoreIdToConfirm,
            bytes32 headerHash,
            SignatoryTotals memory signedTotals,
            bytes32 signatoryRecordHash
        ) = checkSignatures(data);
        emit log_named_uint("entire signature checking gas", g - gasleft());

        require(dataStoreIdToConfirm > 0 && dataStoreIdToConfirm < dataStoreId(), "DataStoreId is invalid");

        /**
         * @notice checks that there is no need for posting a deposit root required for proving
         * the new staking of ETH into Ethereum.
         */
        /**
         @dev for more details, see "depositPOSProof" in EigenLayrDeposit.sol.
         */
        require(
            dataStoreIdToConfirm % depositRootInterval != 0,
            "Must post a deposit root now"
        );

        // record the compressed information pertaining to this particular dump
        /**
         @notice signatoryRecordHash records pubkey hashes of DataLayr operators who didn't sign
         */
        require(dataStoreIdToSignatureHash[dataStoreIdToConfirm] == bytes32(0), "Datastore has already been confirmed");
        dataStoreIdToSignatureHash[dataStoreIdToConfirm] = signatoryRecordHash;

        // call DataLayr contract to check whether quorum is satisfied or not and record it
        dataLayr.confirm(
            dataStoreIdToConfirm,
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
            uint32 dataStoreIdToConfirm,
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
            dataStoreIdToConfirm % depositRootInterval == 0,
            "Shouldn't post a deposit root now"
        );

        // record the compressed information on all the DataLayr nodes who signed
        /**
         @notice signatoryRecordHash records pubkey hashes of DataLayr operators who didn't sign
         */
        dataStoreIdToSignatureHash[dataStoreIdToConfirm] = signatoryRecordHash;

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
            dataStoreIdToConfirm,
            headerHash,
            signedTotals.ethStakeSigned,
            signedTotals.eigenStakeSigned,
            signedTotals.totalEthStake,
            signedTotals.totalEigenStake
        );
    }

    /**
     @notice This is used by a DataLayr operator to make claim on the @param amount that they deserve 
             for their service since their last payment until @param toDataStoreId  
     **/
    function commitPayment(uint32 toDataStoreId, uint120 amount) external {
        IDataLayrRegistry dlRegistry = IDataLayrRegistry(
            address(repository.voteWeigher())
        );

        // only registered DataLayr operators can call
        require(
            dlRegistry.getOperatorType(msg.sender) != 0,
            "Only registered operators can call this function"
        );

        require(toDataStoreId <= dataStoreId(), "Cannot claim future payments");

        // operator puts up collateral which can be slashed in case of wrongful payment claim
        collateralToken.transferFrom(
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
            fromDataStoreId = dlRegistry.getFromDataStoreIdForOperator(msg.sender);

            require(fromDataStoreId < toDataStoreId, "invalid payment range");

            // record the payment information pertaining to the operator
            operatorToPayment[msg.sender] = Payment(
                fromDataStoreId,
                toDataStoreId,
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
        fromDataStoreId = operatorToPayment[msg.sender].toDataStoreId;

        require(fromDataStoreId < toDataStoreId, "invalid payment range");

        // update the record for the commitment to payment made by the operator
        operatorToPayment[msg.sender] = Payment(
            fromDataStoreId,
            toDataStoreId,
            uint32(block.timestamp),
            amount,
            0,
            paymentFraudProofCollateral
        );

        emit PaymentCommit(msg.sender, fromDataStoreId, toDataStoreId, amount);
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
     @notice this function returns the compressed record on the signatures of DataLayr nodes 
             that aren't part of the quorum for this @param _dataStoreId.
     */
    function getDataStoreIdSignatureHash(uint32 _dataStoreId)
        public
        view
        returns (bytes32)
    {
        return dataStoreIdToSignatureHash[_dataStoreId];
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

    /// @notice returns the time when the task, associated with taskHash, was created
    function getTaskCreationTime(bytes32 taskHash)
        public
        view
        returns (uint256)
    {
        (, uint32 initTime, ,  ) = dataLayr.dataStores(taskHash);
        uint256 timeCreated = uint256(initTime);
        if (timeCreated != 0) {
            return timeCreated;
        } else {
            return type(uint256).max;
        }
    }

    /// @notice returns the time when the task, associated with taskHash, will expire
    function getTaskExpiry(bytes32 taskHash)
        external
        view
        returns (uint256)
    {
        (, uint32 initTime, uint32 storePeriodLength, ) = dataLayr.dataStores(
            taskHash
        );
        uint256 timeCreated = uint256(initTime);
        if (timeCreated != 0) {
            return (timeCreated + storePeriodLength);
        } else {
            return type(uint256).max;
        }
    }


    function getDataStoreIdsForDuration(uint8 duration, uint256 timestamp) external view returns(bytes32) {
        return dataStoreIdsForDuration[duration][timestamp];
    }

    // TODO: actually write this function
    function dataStoreIdToFee(uint32) external pure returns (uint96) {
        return 0;
    }


    function incrementDataStoresForDuration(uint8 duration) public {
        if(duration==1){
            ++dataStoresForDuration.one_duration;
        }
        if(duration==2){
            ++dataStoresForDuration.two_duration;
        }
        if(duration==3){
            ++dataStoresForDuration.three_duration;
        }
        if(duration==4){
            ++dataStoresForDuration.four_duration;
        }
        if(duration==5){
            ++dataStoresForDuration.five_duration;
        }
        if(duration==6){
            ++dataStoresForDuration.six_duration;
        }
        if(duration==7){
            ++dataStoresForDuration.seven_duration;
        }

    }

    function getDataStoresForDuration(uint8 duration) public returns(uint32){
        if(duration==1){
            return dataStoresForDuration.one_duration;
        }
        if(duration==2){
            return dataStoresForDuration.two_duration;
        }
        if(duration==3){
            return dataStoresForDuration.three_duration;
        }
        if(duration==4){
            return dataStoresForDuration.four_duration;
        }
        if(duration==5){
            return dataStoresForDuration.five_duration;
        }
        if(duration==6){
            return dataStoresForDuration.six_duration;
        }
        if(duration==7){
            return dataStoresForDuration.seven_duration;
        }

    }

    function dataStoreId() public returns (uint32){
        return dataStoresForDuration.dataStoreId;
    }

    // function getDataStoreIdsForDuration(uint8 duration, uint256 timestamp) public view returns(DataStoreMetadata memory) {
    //     return dataStoreIdsForDuration[duration][timestamp][0];
    // }

    /* function removed for now since it tries to modify an immutable variable
    function setPaymentToken(
        IERC20 _paymentToken
    ) public onlyRepositoryGovernance {
        paymentToken = _paymentToken;
    }
*/
}
