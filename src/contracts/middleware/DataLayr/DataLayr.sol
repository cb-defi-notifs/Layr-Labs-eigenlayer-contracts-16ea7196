// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
/**
 * @title DataLayr
 * @dev L1 contracts that handles DataLayr Node registration
 *
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IDataLayr.sol";
import "../../interfaces/IQueryManager.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


/**
 * @notice This is the contract for 
 */
contract DataLayr is Ownable, IDataLayr {
    using ECDSA for bytes32;

    // the current disperser for this DataLayr
    address public currDisperser;

    // the DataLayr query manager
    IQueryManager public queryManager;

    // percentage of Eigen that DataLayr nodes who have agreed to serve the request
    // need to hold in aggregate for achieving quorum 
    uint128 eigenSignedThresholdPercentage;

    // percentage of ETH that DataLayr nodes who have agreed to serve the request
    // need to hold in aggregate for achieving quorum 
    uint128 ethSignedThresholdPercentage;

    // Data Store 
    struct DataStore {
        uint48 dumpNumber;
        uint32 initTime; //when the store was initiated
        uint32 storePeriodLength; //when store expires
        address submitter; //address approved to submit signatures for this datastore
        bool commited; //whether the data has been certified available
    }

    mapping(bytes32 => DataStore) public dataStores;

    // Constructor
    constructor(address currDisperser_) {
        currDisperser = currDisperser_;
    }

    function setQueryManager(IQueryManager _queryManager) public onlyOwner {
        queryManager = _queryManager;
    }

    // Precommit
    function initDataStore(
        uint48 dumpNumber,
        bytes32 ferkleRoot,
        uint32 totalBytes,
        uint32 storePeriodLength,
        address submitter
    ) external {
        require(msg.sender == currDisperser, "Only current disperser can init");
        require(
            dataStores[ferkleRoot].initTime == 0,
            "Data store has already been inited"
        );

        //initializes data store

        // Create datastore
        dataStores[ferkleRoot] = DataStore(
            dumpNumber,
            uint32(block.timestamp),
            storePeriodLength,
            submitter,
            false
        );
    }


    // Commit
        // bytes32[] calldata rs,
        // bytes32[] calldata ss,
        // uint8[] calldata vs

    function confirm(
        uint256 dumpNumber,
        bytes32 ferkleRoot,
        address submitter,
        uint256 ethStakeSigned,
        uint256 eigenStakeSigned,
        uint256 totalEthStake,
        uint256 totalEigenStake
    ) external  {
        DataStore storage dataStore = dataStores[ferkleRoot];
        //TODO: check if eth and eigen are sufficient
        require(msg.sender == currDisperser, "Only current disperser can call this function");
        require(
            submitter == dataStore.submitter,
            "Not authorized to submit signatures for this datastore"
        );
        require(
            dumpNumber == dataStore.dumpNumber,
            "Dump Number is incorrect"
        );
        require(
            !dataStores[ferkleRoot].commited,
            "Data store already has already been committed"
        );
        //require that signatories own at least a threshold percentage of eth and eigen
        require(ethStakeSigned*100/totalEthStake >= ethSignedThresholdPercentage 
                && eigenStakeSigned*100/totalEigenStake >= eigenSignedThresholdPercentage, 
                "signatories do not own at least a threshold percentage of eth and eigen");
        dataStores[ferkleRoot].commited = true;
    }
    // Setters and Getters

    function setEigenSignatureThreshold(uint128 _eigenSignedThresholdPercentage) public onlyOwner {
        eigenSignedThresholdPercentage = _eigenSignedThresholdPercentage;
    }

    function setEthSignatureThreshold(uint128 _ethSignedThresholdPercentage) public onlyOwner {
        ethSignedThresholdPercentage = _ethSignedThresholdPercentage;
    }
}
