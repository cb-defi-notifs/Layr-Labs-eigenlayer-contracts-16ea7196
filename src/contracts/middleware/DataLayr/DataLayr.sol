// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IDataLayr.sol";
import "../../interfaces/IRepository.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


/**
 * @notice The functionalities of this contract are:
 *            - initializing and asserting the metadata, corresponding to a particular 
 *              assertion of data in DataLayr, into settlement layer.  
 *            - confirming that quorum has been obtained for storing data in DataLayr  
 */
contract DataLayr is Ownable, IDataLayr {
    using ECDSA for bytes32;

    // the DataLayr repository
    IRepository public repository;

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
        uint48 dumpNumber,
        bytes32 headerHash,
        uint32 totalBytes,        
        uint32 initTime,
        uint32 storePeriodLength
    );

    event ConfirmDataStore(
        uint48 dumpNumber,
        bytes32 headerHash
    );

    /**
     * @notice data structure for storing metadata on a particular assertion of data 
     *         into the DataLayr 
     */
    struct DataStore {
        uint48 dumpNumber;

        // time when this store was initiated
        uint32 initTime; 

        // time when obligation for storing this corresponding data by DataLayr nodes expires
        uint32 storePeriodLength;  

        // indicates whether quorm of signatures from DataLayr has been obtained or not
        bool commited; 
    }


    /**
     * @notice a mapping between the ferkle root of the data that has been asserted into
     *         DataLayr and the associated metadata that is being asserted into settlement
     *         layer.  
     */
    mapping(bytes32 => DataStore) public dataStores;

    modifier onlyServiceManager() {
        require(msg.sender == address(repository.serviceManager()), "Only service manager can call this");
        _;
    }

    function setRepository(IRepository _repository) public onlyOwner {
        repository = _repository;
    }



    /**
     * @notice Used for precommitting for the data that would be asserted into DataLayr.
     *         This precomit process includes asserting metadata.   
     */
    /**
     * @param headerHash is the commitment to the data that is being asserted into DataLayr,
     * @param storePeriodLength for which the data has to be stored by the DataLayr nodes, 
     * @param totalBytes  is the size of the data ,
     */
    function initDataStore(
        uint48 dumpNumber,
        bytes32 headerHash,
        uint32 totalBytes,
        uint32 storePeriodLength
    ) external onlyServiceManager {
        require(
            dataStores[headerHash].initTime == 0,
            "Data store has already been initialized"
        );

        //initializes data store
        uint32 initTime = uint32(block.timestamp);

        // initialize and record the datastore
        dataStores[headerHash] = DataStore(
            dumpNumber,
            initTime,
            storePeriodLength,
            false
        );

        
        emit InitDataStore(dumpNumber, headerHash, totalBytes, initTime, storePeriodLength);
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
        uint48 dumpNumber,
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
            dumpNumber == dataStore.dumpNumber,
            "Dump Number is incorrect"
        );

        // there can't be multiple signature commitments into settlement layer for same data
        require(
            !dataStores[headerHash].commited,
            "Data store already has already been committed"
        );

        // check that signatories own at least a threshold percentage of eth 
        // and eigen, thus, implying quorum has been acheieved
        require(ethStakeSigned*100/totalEthStake >= ethSignedThresholdPercentage 
                && eigenStakeSigned*100/totalEigenStake >= eigenSignedThresholdPercentage, 
                "signatories do not own at least a threshold percentage of eth and eigen");

        // record that quorum has been achieved 
        dataStores[headerHash].commited = true;

        emit ConfirmDataStore(dumpNumber, headerHash);
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
