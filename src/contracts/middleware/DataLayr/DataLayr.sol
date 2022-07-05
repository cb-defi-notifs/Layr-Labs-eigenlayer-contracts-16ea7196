// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayr.sol";
import "../../interfaces/IRepository.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../../permissions/RepositoryAccess.sol";
import "forge-std/Test.sol";



/**
 * @notice The functionalities of this contract are:
 *            - initializing and asserting the metadata, corresponding to a particular 
 *              assertion of data in DataLayr, into Ethereum.  
 *            - confirming that quorum has been obtained for storing data in DataLayr  
 */
contract DataLayr is Ownable, IDataLayr, RepositoryAccess, DSTest {
    // constant used to constrain the age of 'blockNumber' specified as input to 'initDataStore' function
    uint256 internal constant BLOCK_STALE_MEASURE = 100;

    /**  
     * @notice percentage of Eigen that DataLayr nodes who have agreed to serve the request
     *         need to hold in aggregate for achieving quorum 
     */
    uint128 public eigenSignedThresholdPercentage = 90;

    /**
     * @notice percentage of ETH that DataLayr nodes who have agreed to serve the request
     *         need to hold in aggregate for achieving quorum 
     */
    uint128 public ethSignedThresholdPercentage = 90;

    event InitDataStore(
        uint32 dataStoreId,
        bytes32 indexed headerHash,
        uint32 totalBytes,        
        uint32 initTime,
        uint32 storePeriodLength,
        uint32 blockNumber,
        bytes header
    );

    event ConfirmDataStore(
        uint32 dataStoreId,
        bytes32 headerHash
    );

    /**
     * @notice data structure for storing metadata on a particular assertion of data 
     *         into the DataLayr 
     */
    struct DataStore {
        // identifying value for the DataStore. incremented for each new 'initDataStore' transaction
        uint32 dataStoreId;

        // time when this store was initiated
        uint32 initTime; 

        // time when obligation for storing this corresponding data by DataLayr nodes expires
        uint32 storePeriodLength;  

        // blockNumber for which the confirmation will consult total + operator stake amounts -- must not be more than 'BLOCK_STALE_MEASURE' in past
        uint32 blockNumber;  

        // // indicates whether quorm of signatures from DataLayr has been obtained or not
        // bool committed; 
    }


    /**
     * @notice a mapping between the ferkle root of the data that has been asserted into
     *         DataLayr and the associated metadata that is being asserted into settlement
     *         layer.  
     */
    mapping(bytes32 => DataStore) public dataStores;

    constructor(IRepository _repository) 
        RepositoryAccess(_repository)
    {
    }

    /**
     * @notice Used for precommitting for the data that would be asserted into DataLayr.
     *         This precomit process includes asserting metadata.   
     */
    /**
     * @param dataStoreId is the dataStoreId to initiate
     * @param headerHash is the commitment to the data that is being asserted into DataLayr,
     * @param totalBytes  is the size of the data ,
     * @param storePeriodLength is time in seconds for which the data has to be stored by the DataLayr nodes, 
     * @param blockNumber for which the confirmation will consult total + operator stake amounts -- must not be more than 'BLOCK_STALE_MEASURE' blocks in past
     */
    function initDataStore(
        uint32 dataStoreId,
        bytes32 headerHash,
        uint32 totalBytes,
        uint32 storePeriodLength,
        uint32 blockNumber,
        bytes calldata header
    ) external onlyServiceManager {
        require(
            dataStores[headerHash].initTime == 0,
            "Data store has already been initialized"
        );
        require(
            blockNumber <= block.number,
            "specified blockNumber is in future"
        );

        require(
            blockNumber >= (block.number - BLOCK_STALE_MEASURE),
            "specified blockNumber is too far in past"
        );


        //initializes data store
        uint32 initTime = uint32(block.timestamp);

        // initialize and record the datastore
        dataStores[headerHash] = DataStore(
            dataStoreId,
            initTime,
            storePeriodLength,
            blockNumber
        );

        
        emit InitDataStore(dataStoreId, headerHash, totalBytes, initTime, storePeriodLength, blockNumber, header);
    }

    /**
     * @notice Used for confirming that quroum of signatures have been obtained from DataLayr
     */
    /**
     * @param headerHash is the commitment to the data that is being asserted into DataLayr,
     * @param ethStakeSigned is the total ETH that has been staked by the DataLayr nodes
     *                       who have signed up to be part of the quorum,     
     * @param eigenStakeSigned is the total Eigen that has been staked by the DataLayr nodes
     *                         who have signed up to be part of the quorum,
     * @param totalEthStake is the total ETH that has been staked in aggregate by all nodes in 
     *                      DataLayr,      
     * @param totalEigenStake is the total Eigen that has been staked in aggregate by all nodes
     *                        in DataLayr.  
     */
    function confirm(
        uint32 dataStoreId,
        bytes32 headerHash,
        uint256 ethStakeSigned,
        uint256 eigenStakeSigned,
        uint256 totalEthStake,
        uint256 totalEigenStake
    ) external onlyServiceManager {
        // accessing the metadata in settlement layer corresponding to the data asserted 
        // into DataLayr
        DataStore storage dataStore = dataStores[headerHash];

        require(
            dataStoreId == dataStore.dataStoreId,
            "DataStoreId is incorrect"
        );

        // there can't be multiple signature commitments into settlement layer for same data
        // require(
        //     !dataStores[headerHash].committed,
        //     "Data store already has already been committed"
        // );

        // check that signatories own at least a threshold percentage of eth 
        // and eigen, thus, implying quorum has been acheieved
        require(ethStakeSigned*100/totalEthStake >= ethSignedThresholdPercentage 
                && eigenStakeSigned*100/totalEigenStake >= eigenSignedThresholdPercentage, 
                "signatories do not own at least a threshold percentage of eth and eigen");

        // record that quorum has been achieved 
        //TODO: We dont need to store this because signatoryRecordHash is a way to check whether a datastore is commited or not
        // dataStores[headerHash].committed = true;

        emit ConfirmDataStore(dataStoreId, headerHash);
    }
    
    
    /**
     * @notice used for setting specifications for quorum.  
     */  
    function setEigenSignatureThreshold(uint128 _eigenSignedThresholdPercentage) public onlyOwner {
        require(_eigenSignedThresholdPercentage <= 100, "percentage must be between 0 and 100 inclusive");
        eigenSignedThresholdPercentage = _eigenSignedThresholdPercentage;
    }
    function setEthSignatureThreshold(uint128 _ethSignedThresholdPercentage) public onlyOwner {
        require(_ethSignedThresholdPercentage <= 100, "percentage must be between 0 and 100 inclusive");
        ethSignedThresholdPercentage = _ethSignedThresholdPercentage;
    }
}
