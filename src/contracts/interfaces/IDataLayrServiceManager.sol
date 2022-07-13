// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IDataLayr.sol";
import "./IServiceManager.sol";
import "./IEigenLayrDelegation.sol";

interface IDataLayrServiceManager is IServiceManager {

    //Relevant metadata for a given datastore
    struct DataStoreMetadata {
        bytes32 headerHash;
        uint32 durationDataStoreId;
        uint32 globalDataStoreId;
        uint32 blockNumber;
        uint96 fee;
        bytes32 signatoryRecordHash;
    }

    //Stores the data required to index a given datastore's metadata
    struct DataStoreSearchData {
        uint8 duration;
        uint256 timestamp;
        uint32 index;
        DataStoreMetadata metadata;
    }

    struct SignatoryRecordMinusDataStoreId {
        bytes32[] nonSignerPubkeyHashes;
        uint256 totalEthStakeSigned;
        uint256 totalEigenStakeSigned;
    }

    function dataStoreId() external view returns (uint32);

    function dataStoreIdToFee(uint32) external view returns (uint96);

    function numPowersOfTau() external view returns(uint48);

    function log2NumPowersOfTau() external view returns(uint48);
    
    function DURATION_SCALE() external view returns(uint256);

    function MAX_DATASTORE_DURATION() external view returns(uint8);

    function getDataStoreIdsForDuration(uint8 duration, uint256 timestamp, uint32 index) external view returns(bytes32);
    
    function totalDataStoresForDuration(uint8 duration) external view returns(uint32);

    function collateralToken() external view returns(IERC20);
}