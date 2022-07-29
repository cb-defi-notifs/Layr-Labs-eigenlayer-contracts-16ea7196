// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../interfaces/IRepository.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/IProofOfStakingOracle.sol";
import "../../interfaces/IDelegationTerms.sol";

import "./DataLayrServiceManagerStorage.sol";
import "../BLSSignatureChecker.sol";

import "../../libraries/BytesLib.sol";
import "../../libraries/Merkle.sol";
import "../../libraries/DataStoreHash.sol";

import "../Repository.sol";
import "./DataLayrChallengeUtils.sol";
import "ds-test/test.sol";

/**
 * @notice This contract is used for:
            - initializing the data store by the disperser
            - confirming the data store by the disperser with inferred aggregated signatures of the quorum
            - doing forced disclosure challenge
            - doing payment challenge
 */
contract DataLayrServiceManager is
    DataLayrServiceManagerStorage,
    BLSSignatureChecker,
    IProofOfStakingOracle
    // ,DSTest
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
        uint32 index,
        bytes32 indexed headerHash,
        bytes header,
        uint32 totalBytes,
        uint32 initTime,
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

    function setDisclosureChallenge(DataLayrDisclosureChallenge _dataLayrDisclosureChallenge) public onlyRepositoryGovernance {
        dataLayrDisclosureChallenge = _dataLayrDisclosureChallenge;
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
        uint32 index;
        {
           // uint g = gasleft();

            bool initializable = false;
            

            for (uint32 i = 0; i < NUM_DS_PER_BLOCK_PER_DURATION; i++){
                if(dataStoreHashesForDurationAtTimestamp[duration][block.timestamp][i] == 0){
                    dataStoreHashesForDurationAtTimestamp[duration][block.timestamp][i] = DataStoreHash.computeDataStoreHash(
                                                                                                headerHash, 
                                                                                                dataStoresForDuration.dataStoreId, 
                                                                                                blockNumber, 
                                                                                                uint96(fee),
                                                                                                bytes32(0)
                                                                                            );
                    initializable = true; 

                    // recording the empty slot
                    index = i;
                    break;   
                }       
            }

            // reverting if no empty slot exists
            require(initializable == true, "number of initDatastores for this duration and block has reached its limit");
        }



        // sanity check on blockNumber
        { 
            require(
                blockNumber <= block.number,
                "specified blockNumber is in future"
            );

            require(
                blockNumber >= (block.number - BLOCK_STALE_MEASURE),
                "specified blockNumber is too far in past"
            );
            
        }


        // emit event to represent initialization of data store
        emit InitDataStore(dataStoresForDuration.dataStoreId, index, headerHash, header, totalBytes, uint32(block.timestamp), storePeriodLength, blockNumber, fee);


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

        if (_latestTime > latestTime) {
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
             bytes32 headerHash,
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
            bytes32 headerHash,
            SignatoryTotals memory signedTotals,
            bytes32 signatoryRecordHash
        ) = checkSignatures(data);

        require(dataStoreIdToConfirm > 0 && dataStoreIdToConfirm < dataStoreId(), "DataStoreId is invalid");

        emit log_bytes32(headerHash);
        emit log_bytes32(signatoryRecordHash);


        /**
         * @notice checks that there is no need for posting an updated deposit root required for proving
         * the new staking of ETH into Ethereum.
         */
        /**
         @dev for more details, see "proveLegacyConsensusLayerDeposit" in EigenLayrDeposit.sol.
         */
        require(
            dataStoreIdToConfirm % depositRootInterval != 0,
            "Must post a deposit root now"
        );

        // check that the provided headerHash matches the one whose signature we just checked!
        require(headerHash == searchData.metadata.headerHash, "submitted headerHash does not match that for checkSignatures");

        //Check if provided calldata matches the hash stored in dataStoreIDsForDuration in initDataStore
        bytes32 dsHash = DataStoreHash.computeDataStoreHash(
                                            searchData.metadata.headerHash, 
                                            searchData.metadata.globalDataStoreId, 
                                            searchData.metadata.blockNumber, 
                                            searchData.metadata.fee,
                                            bytes32(0)
                                            );

        // emit log_named_uint("compute hash", g-gasleft());


        require(    
                dataStoreHashesForDurationAtTimestamp[searchData.duration][searchData.timestamp][searchData.index] == dsHash,
                "provided calldata does not match corresponding stored hash from initDataStore"
        );
        

        // computing a new DataStoreIdsForDuration hash that includes the signatory record as well 
        bytes32 newDsHash = DataStoreHash.computeDataStoreHash(
                                            searchData.metadata.headerHash, 
                                            searchData.metadata.globalDataStoreId, 
                                            searchData.metadata.blockNumber, 
                                            searchData.metadata.fee,
                                            signatoryRecordHash
                                            );

        //storing new hash
        dataStoreHashesForDurationAtTimestamp[searchData.duration][searchData.timestamp][searchData.index] = newDsHash;

        // check that signatories own at least a threshold percentage of eth 
        // and eigen, thus, implying quorum has been acheieved
        require(signedTotals.ethStakeSigned * 100/signedTotals.totalEthStake >= ethSignedThresholdPercentage 
                && signedTotals.eigenStakeSigned*100/signedTotals.totalEigenStake >= eigenSignedThresholdPercentage, 
                "signatories do not own at least a threshold percentage of eth and eigen");

        // record that quorum has been achieved 
        //TODO: We dont need to store this because signatoryRecordHash is a way to check whether a datastore is commited or not
        // dataStores[headerHash].committed = true;

        emit ConfirmDataStore(dataStoresForDuration.dataStoreId, headerHash);

    }

    // called in the event of challenge resolution
    function slashOperator(address operator) external {
        require(
            msg.sender == address(dataLayrLowDegreeChallenge) ||
            msg.sender == address(dataLayrDisclosureChallenge) ||
            msg.sender == address(dataLayrBombVerifier) ||
            msg.sender == address(ephemeralKeyRegistry) ||
            msg.sender == address(dataLayrPaymentManager),
            "Only challenge resolvers can slash operators"
        );
        ISlasher(investmentManager.slasher()).slashOperator(operator);
    }

   

    function getDepositRoot(uint256 blockNumber) public view returns (bytes32) {
        return depositRoots[blockNumber];
    }

    function setFeePerBytePerTime(uint256 _feePerBytePerTime)
        public
        onlyRepositoryGovernance
    {
        feePerBytePerTime = _feePerBytePerTime;
    }

    function getDataStoreIdsForDuration(uint8 duration, uint256 timestamp, uint32 index) external view returns(bytes32) {
        return dataStoreHashesForDurationAtTimestamp[duration][timestamp][index];
    }

    // TODO: de-duplicate functions
    function dataStoreIdToFee(uint32 _dataStoreId) external pure returns (uint96) {
        return uint96(taskNumberToFee(_dataStoreId));
    }

    // TODO: actually write this function
    function taskNumberToFee(uint32) public pure returns(uint256) {
        return 0;
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
    function getDataStoresForDuration(uint8 duration) public view returns(uint32){
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

    // TODO: de-duplicate functions
    function dataStoreId() public view returns (uint32){
        return dataStoresForDuration.dataStoreId;
    }

    function taskNumber() public view returns (uint32){
        return dataStoresForDuration.dataStoreId;
    }

    //TODO: CORRECT CALLDATALOAD SLOTS

    /** 
     @dev This calldata is of the format:
            <
             bytes32 headerHash,
             uint32 signatoryRecordHash
             uint32 blockNumber
             uint32 taskNumber
             uint32 numberOfNonSigners,
             uint256[numberOfSigners][4] pubkeys of nonsigners,
             uint32 apkIndex,
             uint256[4] apk,
             uint256[2] sigma
            >
     */
    function stakeWithdrawalVerification(bytes calldata, uint256 initTimestamp, uint256 unlockTime) external  {
        bytes32 headerHash;
        bytes32 signatoryRecordHash;
        uint32 _dataStoreId; 
        uint32 blockNumber; 
        uint96 fee;
        uint8 duration; 
        uint256 dsInitTime; 
        uint32 index;


        uint256 pointer = 132;
        
        assembly {
            headerHash := calldataload(pointer)
            signatoryRecordHash:= calldataload(add(pointer, 32))  
            _dataStoreId := shr(224, calldataload(add(pointer, 64)))  
            blockNumber := shr(224, calldataload(add(pointer, 68))) 
            fee := shr(160, calldataload(add(pointer, 72)))
            duration := shr(248, calldataload(add(pointer, 84)))
            dsInitTime := calldataload(add(pointer, 85))
            index := shr(224, calldataload(add(pointer, 117)))
        }

        bytes32 dsHash = DataStoreHash.computeDataStoreHash(headerHash, _dataStoreId, blockNumber, fee, signatoryRecordHash);
        require(
            dataStoreHashesForDurationAtTimestamp[duration][dsInitTime][index] == dsHash, "provided calldata does not match corresponding stored hash from (initDataStore)");

        //now we check if the dataStore is still active at the time
        //TODO: check if the duration is in days or seconds
        require(
            initTimestamp > dsInitTime
                 &&
                unlockTime <
                dsInitTime + duration*86400,
            "task does not meet requirements"
        );

    }

    /* function removed for now since it tries to modify an immutable variable
    function setPaymentToken(
        IERC20 _paymentToken
    ) public onlyRepositoryGovernance {
        paymentToken = _paymentToken;
    }
*/

// TODO: re-implement this function
//    /**
//     * @notice This function is used when the  DataLayr is used to update the POSt hash
//     *         along with the regular assertion of data into the DataLayr by the disperser. This
//     *         function enables
//     *          - disperser to notify that signatures, comprising of hash(depositRoot || headerHash),
//     *            from quorum of DataLayr nodes have been obtained,
//     *          - check that each of the signatures are valid,
//     *          - store the POSt hash, given by depositRoot,
//     *          - call the DataLayr contract to check  whether quorum has been achieved or not.
//     */
//    function confirmDataStoreWithPOSt(
//        bytes32 depositRoot,
//        bytes32 headerHash,
//        bytes calldata data
//    ) external payable {
//        // verify the signatures that disperser is claiming to be that of DataLayr operators
//        // who have agreed to be in the quorum
//        (
//            uint32 dataStoreIdToConfirm,
//            bytes32 depositFerkleHash,
//            ,
//            bytes32 signatoryRecordHash
//        ) = checkSignatures(data);

//        /**
//          @notice checks that there is need for posting a deposit root required for proving
//          the new staking of ETH into Ethereum. 
//         */
//        /**
//          @dev for more details, see "depositPOSProof" in EigenLayrDeposit.sol.
//         */
//        require(
//            dataStoreIdToConfirm % depositRootInterval == 0,
//            "Shouldn't post a deposit root now"
//        );

//        // record the compressed information on all the DataLayr nodes who signed
//        /**
//         @notice signatoryRecordHash records pubkey hashes of DataLayr operators who didn't sign
//         */
//        dataStoreIdToSignatureHash[dataStoreIdToConfirm] = signatoryRecordHash;

//        /**
//         * when posting a deposit root, DataLayr nodes will sign hash(depositRoot || headerHash)
//         * instead of the usual headerHash, so the submitter must specify the preimage
//         */
//        require(
//            keccak256(abi.encodePacked(depositRoot, headerHash)) ==
//                depositFerkleHash,
//            "Ferkle or deposit root is incorrect"
//        );

//        // record the deposit root (POSt hash)
//        depositRoots[block.number] = depositRoot;

//        // call DataLayr contract to check whether quorum is satisfied or not and record it
//        
//    }
}
