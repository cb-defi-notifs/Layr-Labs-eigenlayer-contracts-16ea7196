// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
/**
 * @title DataLayr
 * @dev L1 contracts that handles DataLayr Node registration
 *
 */

import "../../interfaces/IERC20.sol";
import "../../interfaces/IDataLayr.sol";
import "../../interfaces/IQueryManager.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DataLayr is Ownable, IDataLayr {
    using ECDSA for bytes32;

    address public currDisperser;
    //the DL query manager
    IQueryManager public queryManager;
    //percentage of eigen that signers need to hold for a quorum
    uint128 eigenSignedThresholdPercentage;
    //percentage of eth that signers need to hold for a quorum
    uint128 ethSignedThresholdPercentage;

    // Data Store
    struct DataStore {
        uint48 dumpNumber;
        uint32 initTime; //when the store was inited
        uint32 storePeriodLength; //when store expires
        address submitter; //address approved to submit signatures for this datastore
        bool commited; //whether the data has been certified available
    }

    event DataStoreInit(
        address initializer, //person initing store
        bytes32 ferkleRoot, //counter-esque id
        uint256 totalBytes //number of bytes in store including redundant chunks, basicall the total number of bytes in all frames of the FRS Merkle Tree
    );

    mapping(bytes32 => DataStore) public dataStores;

    event Commit(
        address disperser,
        bytes32 ferkleRoot
    );

    // Misc
    mapping(bytes32 => mapping(address => bool)) public isCodingProofDLNActive;

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

        emit DataStoreInit(
            msg.sender,
            ferkleRoot,
            totalBytes
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
        uint128 ethStakeSigned,
        uint128 eigenStakeSigned
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
        require(ethStakeSigned*100/queryManager.totalEthStaked() >= ethSignedThresholdPercentage 
                && eigenStakeSigned*100/queryManager.totalEigenStaked() >= eigenSignedThresholdPercentage, 
                "signatories do not own at least a threshold percentage of eth and eigen");
        dataStores[ferkleRoot].commited = true;
        emit Commit(
            msg.sender,
            ferkleRoot
        );
    }
    // Setters and Getters

    function setEigenSignatureThreshold(uint128 _eigenSignedThresholdPercentage) public onlyOwner {
        eigenSignedThresholdPercentage = _eigenSignedThresholdPercentage;
    }

    function setEthSignatureThreshold(uint128 _ethSignedThresholdPercentage) public onlyOwner {
        ethSignedThresholdPercentage = _ethSignedThresholdPercentage;
    }
}
