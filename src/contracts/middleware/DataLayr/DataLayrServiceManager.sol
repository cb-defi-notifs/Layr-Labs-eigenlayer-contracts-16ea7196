// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../interfaces/IRepository.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/IDelegationTerms.sol";

import "./DataLayrServiceManagerStorage.sol";
import "../BLSSignatureChecker.sol";

import "../../libraries/BytesLib.sol";
import "../../libraries/Merkle.sol";
import "../../libraries/DataStoreUtils.sol";

import "../Repository.sol";
import "./DataLayrChallengeUtils.sol";


/**
 * @notice This contract is used for:
            - initializing the data store by the disperser
            - confirming the data store by the disperser with inferred aggregated signatures of the quorum
            - doing payment challenge
 */
contract DataLayrServiceManager is
    DataLayrServiceManagerStorage,
    BLSSignatureChecker
{
    using BytesLib for bytes;


    /**********************
        CONSTANTS
     **********************/
    //TODO: mechanism to change any of these values?
    uint32 internal constant MIN_STORE_SIZE = 32;
    uint32 internal constant MAX_STORE_SIZE = 4e9;
    uint32 internal constant MIN_STORE_LENGTH = 60;
    uint32 internal constant MAX_STORE_LENGTH = 604800;
    uint256 internal constant BLOCK_STALE_MEASURE = 100;



    /**********************
        ERROR MESSAGES
     **********************/
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



    uint128 public eigenSignedThresholdPercentage = 90;
    uint128 public ethSignedThresholdPercentage = 90;

    DataStoresForDuration public dataStoresForDuration;



    /*************
        EVENTS
     *************/
    event InitDataStore(
        uint32 dataStoreId,
        uint32 durationDataStoreId,
        uint32 index,
        bytes32 indexed headerHash,
        bytes header,
        uint32 totalBytes,
        uint32 storePeriodLength,
        uint32 blockNumber,
        uint256 fee
    );

    event ConfirmDataStore(
        uint32 dataStoreId,
        bytes32 headerHash
    );



    constructor(
        IInvestmentManager _investmentManager,
        IEigenLayrDelegation _eigenLayrDelegation,
        IRepository _repository,
        IERC20 _collateralToken,
        uint256 _feePerBytePerTime
    ) 
        DataLayrServiceManagerStorage(_investmentManager, _eigenLayrDelegation, _collateralToken)
        BLSSignatureChecker(_repository)
    {
        feePerBytePerTime = _feePerBytePerTime;
        dataStoresForDuration.dataStoreId = 1;
        dataStoresForDuration.latestTime = 1;
        
    }

    function setLowDegreeChallenge(DataLayrLowDegreeChallenge _dataLayrLowDegreeChallenge) public onlyRepositoryGovernance {
        dataLayrLowDegreeChallenge = _dataLayrLowDegreeChallenge;
    }

    function setBombVerifier(DataLayrBombVerifier _dataLayrBombVerifier) public onlyRepositoryGovernance {
        dataLayrBombVerifier = _dataLayrBombVerifier;
    }

    function setPaymentManager(DataLayrPaymentManager _dataLayrPaymentManager) public onlyRepositoryGovernance {
        dataLayrPaymentManager = _dataLayrPaymentManager;
    }

    function setEphemeralKeyRegistry(EphemeralKeyRegistry _ephemeralKeyRegistry) public onlyRepositoryGovernance {
        ephemeralKeyRegistry = _ephemeralKeyRegistry;
    }

    /**
      @notice This function is used for
               - notifying in the Ethereum that the disperser has asserted the data blob
                 into DataLayr and is waiting for obtaining quorum of DataLayr operators to sign,
               - asserting the metadata corresponding to the data asserted into DataLayr
               - escrow the service fees that DataLayr operators will receive from the disperser
                 on account of their service.
              
              This function returns the index of the data blob in dataStoreIdsForDuration[duration][block.timestamp]
     */
    /**
      @param feePayer is the address of the balance paying the fees for this datastore. check DataLayrPaymentManager for further details
      @param confirmer is the address that must confirm the datastore
      @param header is the summary of the data that is being asserted into DataLayr,
            CRITIC -- need to describe header structure
      @param duration for which the data has to be stored by the DataLayr operators.
              This is a quantized parameter that describes how many factors of DURATION_SCALE
              does this data blob needs to be stored. The quantization process comes from ease of 
              implementation in DataLayrBombVerifier.sol.
      @param totalBytes  is the size of the data ,
      @param blockNumber is the block number in Ethereum for which the confirmation will 
             consult total + operator stake amounts. 
              -- must not be more than 'BLOCK_STALE_MEASURE' (defined in DataLayr) blocks in past
     */
    function initDataStore(
        address feePayer,
        address confirmer,
        bytes calldata header,
        uint8 duration,
        uint32 totalBytes,
        uint32 blockNumber
    ) external payable returns(uint32){
        bytes32 headerHash = keccak256(header);

        /********************************************
          sanity check on the parameters of data blob  
         ********************************************/
        if (totalBytes < MIN_STORE_SIZE) {
            revert StoreTooSmall(MIN_STORE_SIZE, totalBytes);
        }

        if (totalBytes > MAX_STORE_SIZE) {
            revert StoreTooLarge(MAX_STORE_SIZE, totalBytes);
        }

        require(duration >= 1 && duration <= MAX_DATASTORE_DURATION, "Invalid duration");

        /***********************
          compute time and fees
         ***********************/
        // computing the actual period for which data blob needs to be stored
        uint32 storePeriodLength = uint32(duration * DURATION_SCALE);

        // evaluate the total service fees that msg.sender has to put in escrow for paying out
        // the DataLayr nodes for their service
        uint256 fee = (totalBytes * feePerBytePerTime) * storePeriodLength;
        
        // require that disperser has sent enough fees to this contract to pay for this datastore.
        // This will revert if the deposits are not high enough due to undeflow.
        dataLayrPaymentManager.payFee(msg.sender, feePayer, fee);

        /*************************************************************************
          Recording the initialization of datablob store along with auxiliary info
         *************************************************************************/
        //store metadata locally to be stored
        IDataLayrServiceManager.DataStoreMetadata memory metadata = 
            IDataLayrServiceManager.DataStoreMetadata({
                headerHash: headerHash, 
                durationDataStoreId: getNumDataStoresForDuration(duration),
                globalDataStoreId: dataStoresForDuration.dataStoreId, 
                blockNumber: blockNumber, 
                fee: uint96(fee),
                confirmer: confirmer,
                signatoryRecordHash: bytes32(0)
            }
        );

        uint32 index;

        {
           // uint g = gasleft();
            //iterate the index throughout the loop
            for (; index < NUM_DS_PER_BLOCK_PER_DURATION; index++){
                if(dataStoreHashesForDurationAtTimestamp[duration][block.timestamp][index] == 0){
                    dataStoreHashesForDurationAtTimestamp[duration][block.timestamp][index] = DataStoreUtils.computeDataStoreHash(metadata);
                    // recording the empty slot
                    break;   
                }       
            }

            // reverting we looped through all of the indecies without finding an empty element
            require(index != NUM_DS_PER_BLOCK_PER_DURATION, "DataLayrServiceManager.initDataStore: number of initDatastores for this duration and block has reached its limit");

        }

        // sanity check on blockNumber
        { 
            require(
                blockNumber <= block.number,
                "DataLayrServiceManager.initDataStore: specified blockNumber is in future"
            );

            require(
                blockNumber >= (block.number - BLOCK_STALE_MEASURE),
                "DataLayrServiceManager.initDataStore: specified blockNumber is too far in past"
            );    
        }

        // emit event to represent initialization of data store
        emit InitDataStore(dataStoresForDuration.dataStoreId, getNumDataStoresForDuration(duration), index, headerHash, header, totalBytes, storePeriodLength, blockNumber, fee);

        /******************************
          Updating dataStoresForDuration 
         ******************************/
        /**
        @notice sets the latest time until which any of the active DataLayr operators that haven't committed
                yet to deregistration are supposed to serve.
        */
        // recording the expiry time until which the DataLayr operators, who sign up to
        // part of the quorum, have to store the data
        uint32 _latestTime = uint32(block.timestamp) + storePeriodLength;

        if (_latestTime > dataStoresForDuration.latestTime) {
            dataStoresForDuration.latestTime = _latestTime;            
        }

        incrementDataStoresForDuration(duration);
        
        // increment the counter
        ++dataStoresForDuration.dataStoreId;
        return index;
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
             bytes32 msgHash,
             uint48 index of the totalStake corresponding to the dataStoreId in the 'totalStakeHistory' array of the BLSRegistryWithBomb
             uint32 numberOfNonSigners,
             uint256[numberOfSigners][4] pubkeys of nonsigners,
             uint32 apkIndex,
             uint256[4] apk,
             uint256[2] sigma
            >
     */
    function confirmDataStore(bytes calldata data, DataStoreSearchData memory searchData) external payable {
        /*******************************************************
         verify the disperser's claim on composition of quorum
         *******************************************************/

        // verify the signatures that disperser is claiming to be of those DataLayr operators 
        // who have agreed to be in the quorum
        (
            uint32 dataStoreIdToConfirm,
            uint32 blockNumberFromTaskHash,
            bytes32 msgHash,
            SignatoryTotals memory signedTotals,
            bytes32 signatoryRecordHash
        ) = checkSignatures(data);


        //make sure that the nodes signed the hash of dsid, headerHash, duration, timestamp, and index to avoid malleability in case of reorgs
        //this keeps bomb and storage conditions stagnant

        require(msgHash == keccak256(abi.encodePacked(dataStoreIdToConfirm, searchData.metadata.headerHash, searchData.duration, searchData.timestamp, searchData.index)), 
                "DataLayrServiceManager.confirmDataStore: msgHash is not consistent with search data");

        //make sure the address confirming is the prespecified `confirmer`
        require(msg.sender == searchData.metadata.confirmer, "DataLayrServiceManager.confirmDataStore: Sender is not authorized to confirm this datastore");
        require(searchData.metadata.signatoryRecordHash == bytes32(0), "DataLayrServiceManager.confirmDataStore: SignatoryRecord must be bytes32(0)");
        require(searchData.metadata.globalDataStoreId == dataStoreIdToConfirm, "DataLayrServiceManager.confirmDataStore: gloabldatastoreid is does not agree with data");
        require(searchData.metadata.blockNumber == blockNumberFromTaskHash, "DataLayrServiceManager.confirmDataStore: blocknumber does not agree with data");




        //Check if provided calldata matches the hash stored in dataStoreIDsForDuration in initDataStore
        //verify consistency of signed data with stored data
        bytes32 dsHash = DataStoreUtils.computeDataStoreHash(searchData.metadata);


        require(    
            dataStoreHashesForDurationAtTimestamp[searchData.duration][searchData.timestamp][searchData.index] == dsHash,
            "DataLayrServiceManager.confirmDataStore: provided calldata does not match corresponding stored hash from initDataStore"
        );

        searchData.metadata.signatoryRecordHash = signatoryRecordHash;

        // computing a new DataStoreIdsForDuration hash that includes the signatory record as well 
        bytes32 newDsHash = DataStoreUtils.computeDataStoreHash(searchData.metadata);


        //storing new hash
        dataStoreHashesForDurationAtTimestamp[searchData.duration][searchData.timestamp][searchData.index] = newDsHash;

        // check that signatories own at least a threshold percentage of eth 
        // and eigen, thus, implying quorum has been acheieved
        require(signedTotals.ethStakeSigned * 100/signedTotals.totalEthStake >= ethSignedThresholdPercentage 
                && signedTotals.eigenStakeSigned*100/signedTotals.totalEigenStake >= eigenSignedThresholdPercentage, 
                "DataLayrServiceManager.confirmDataStore: signatories do not own at least a threshold percentage of eth and eigen");


        emit ConfirmDataStore(dataStoresForDuration.dataStoreId, searchData.metadata.headerHash);

    }

    // called in the event of challenge resolution
    function freezeOperator(address operator) external {
        require(
            msg.sender == address(dataLayrLowDegreeChallenge) ||
            msg.sender == address(dataLayrBombVerifier) ||
            msg.sender == address(ephemeralKeyRegistry) ||
            msg.sender == address(dataLayrPaymentManager),
            "DataLayrServiceManager.slashOperator: Only challenge resolvers can slash operators"
        );
        ISlasher(investmentManager.slasher()).freezeOperator(operator);
    }

    function setFeePerBytePerTime(uint256 _feePerBytePerTime)
        public
        onlyRepositoryGovernance
    {
        feePerBytePerTime = _feePerBytePerTime;
    }

    function getDataStoreHashesForDurationAtTimestamp(uint8 duration, uint256 timestamp, uint32 index) external view returns(bytes32) {
        return dataStoreHashesForDurationAtTimestamp[duration][timestamp][index];
    }

    /**
     @notice increments the number of data stores for the @param duration
     */
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

    /**
     @notice returns the number of data stores for the @param duration
     */
    /// CRITIC -- change the name to `getNumDataStoresForDuration`?
    function getNumDataStoresForDuration(uint8 duration) public view returns(uint32){
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
        return 0;
    }
    
    function taskNumber() public view returns (uint32){
        return dataStoresForDuration.dataStoreId;
    }

    /** 
     * @param packedDataStoreSearchData should be the same format as the output of `DataStoreUtils.packDataStoreSearchData(dataStoreSearchData)`
     */
    function stakeWithdrawalVerification(bytes calldata packedDataStoreSearchData, uint256 initTimestamp, uint256 unlockTime) external view {
        IDataLayrServiceManager.DataStoreSearchData memory searchData = DataStoreUtils.unpackDataStoreSearchData(packedDataStoreSearchData);
        bytes32 dsHash = DataStoreUtils.computeDataStoreHash(searchData.metadata);
        require(
            dataStoreHashesForDurationAtTimestamp[searchData.duration][searchData.timestamp][searchData.index] == dsHash,
            "DataLayrServiceManager.stakeWithdrawalVerification: provided calldata does not match corresponding stored hash from (initDataStore)"
        );

        /**
         *  Now we check that the specified DataStore was created *at or before*  the `initTimestamp`, i.e. when the user undelegated, deregistered, etc. *AND*
         *  that the user's funds are set to unlock *prior* to the expiration of the DataStore.
         *  In other words, we are checking that a user was active when the specified DataStore was created, and is trying to unstake/undelegate/etc. funds prior
         *  to them fully serving out their commitment to storing their share of the data.
         */
        require(
            (initTimestamp >= searchData.timestamp)
                &&
            (unlockTime < searchData.timestamp + (searchData.duration * DURATION_SCALE)),
            "DataLayrServiceManager.stakeWithdrawalVerification: task does not meet requirements"
        );

    }

    function latestTime() external view returns (uint32) {
        return dataStoresForDuration.latestTime;
    }

    /* function removed for now since it tries to modify an immutable variable
    function setPaymentToken(
        IERC20 _paymentToken
    ) public onlyRepositoryGovernance {
        paymentToken = _paymentToken;
    }
    */
}
