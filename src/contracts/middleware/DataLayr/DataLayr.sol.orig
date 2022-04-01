// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IDataLayr.sol";
import "../../interfaces/IQueryManager.sol";
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

    // the DataLayr query manager
    IQueryManager public queryManager;

    /**  
     * @notice percentage of Eigen that DataLayr nodes who have agreed to serve the request
     *         need to hold in aggregate for achieving quorum 
     */
    uint128 eigenSignedThresholdPercentage;

    /**
     * @notice percentage of ETH that DataLayr nodes who have agreed to serve the request
     *         need to hold in aggregate for achieving quorum 
     */
    uint128 ethSignedThresholdPercentage;


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

    function setQueryManager(IQueryManager _queryManager) public onlyOwner {
        queryManager = _queryManager;
    }



    /**
     * @notice Used for precommitting for the data that would be asserted into DataLayr.
     *         This precomit process includes asserting metadata.   
     */
    /**
     * @param ferkleRoot is the commitment to the data that is being asserted into DataLayr,
     * @param storePeriodLength for which the data has to be stored by the DataLayr nodes, 
     * @param totalBytes  is the size of the data ,
     */
    function initDataStore(
        uint48 dumpNumber,
        bytes32 ferkleRoot,
        uint32 totalBytes,
        uint32 storePeriodLength
    ) external {
        // CRITIC: would it be better to have a modifier for this check as it is 
        //         also used in confirm ?
        require(msg.sender == address(queryManager.feeManager()), "Only fee manager can init");


        require(
            dataStores[ferkleRoot].initTime == 0,
            "Data store has already been initialized"
        );

        //initializes data store

        // initialize and record the datastore
        dataStores[ferkleRoot] = DataStore(
            dumpNumber,
            uint32(block.timestamp),
            storePeriodLength,
            false
        );
    }


    // Commit
        // bytes32[] calldata rs,
        // bytes32[] calldata ss,
        // uint8[] calldata vs

    /**
     * @notice Used for confirming that quroum of signatures have been obtained from DataLayr
     */
    /**
     * @param ferkleRoot is the commitment to the data that is being asserted into DataLayr,
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
        uint256 dumpNumber,
        bytes32 ferkleRoot,
        uint256 ethStakeSigned,
        uint256 eigenStakeSigned,
        uint256 totalEthStake,
        uint256 totalEigenStake
    ) external  {
        // accessing the metadata in settlement layer cooresponding to the data asserted 
        // into DataLayr
        DataStore storage dataStore = dataStores[ferkleRoot];

        //TODO: check if eth and eigen are sufficient
        require(msg.sender == address(queryManager.feeManager()), "Only fee manager can init");

        require(
            dumpNumber == dataStore.dumpNumber,
            "Dump Number is incorrect"
        );

        // there can't be multiple signature commitments into settlement layer for same data
        require(
            !dataStores[ferkleRoot].commited,
            "Data store already has already been committed"
        );

        // check that signatories own at least a threshold percentage of eth 
        // and eigen, thus, implying quorum has been acheieved
        require(ethStakeSigned*100/totalEthStake >= ethSignedThresholdPercentage 
                && eigenStakeSigned*100/totalEigenStake >= eigenSignedThresholdPercentage, 
                "signatories do not own at least a threshold percentage of eth and eigen");

        // record that quorum has been achieved 
        dataStores[ferkleRoot].commited = true;
    }
    
    
    /**
     * @notice used for setting specifications for quorum.  
     */  
    function setEigenSignatureThreshold(uint128 _eigenSignedThresholdPercentage) public onlyOwner {
        eigenSignedThresholdPercentage = _eigenSignedThresholdPercentage;
    }
    function setEthSignatureThreshold(uint128 _ethSignedThresholdPercentage) public onlyOwner {
        ethSignedThresholdPercentage = _ethSignedThresholdPercentage;
    }
}
