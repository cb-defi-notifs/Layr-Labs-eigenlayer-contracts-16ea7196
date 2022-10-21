// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IServiceManager.sol";
import "./IEigenLayrDelegation.sol";
import "./IDataLayrPaymentManager.sol";


interface IDataLayrServiceManager is IServiceManager {
    //Relevant metadata for a given datastore
    struct DataStoreMetadata {
        bytes32 headerHash;
        uint32 durationDataStoreId;
        uint32 globalDataStoreId;
        uint32 blockNumber;
        uint96 fee;
        address confirmer;
        bytes32 signatoryRecordHash;
    }

    //Stores the data required to index a given datastore's metadata
    struct DataStoreSearchData {
        DataStoreMetadata metadata;
        uint8 duration;
        uint256 timestamp;
        uint32 index;
    }

    struct SignatoryRecordMinusDataStoreId {
        bytes32[] nonSignerPubkeyHashes;
        uint256 totalEthStakeSigned;
        uint256 totalEigenStakeSigned;
    }

    struct DataStoresForDuration {
        uint32 one_duration;
        uint32 two_duration;
        uint32 three_duration;
        uint32 four_duration;
        uint32 five_duration;
        uint32 six_duration;
        uint32 seven_duration;
        uint32 dataStoreId;
        uint32 latestTime;
    }

    struct DataStoreHashInputs {
        bytes32 headerHash;
        uint32 dataStoreId;
        uint32 blockNumber;
        uint256 fee;
    }

    function initDataStore(
        address feePayer,
        address confirmer,
        uint8 duration,
        uint32 blockNumber,
        uint32 totalOperatorsIndex,
        bytes calldata header
    )
        external
        returns (uint32);

    function confirmDataStore(bytes calldata data, DataStoreSearchData memory searchData) external;

    function numPowersOfTau() external view returns (uint48);

    function log2NumPowersOfTau() external view returns (uint48);

    function DURATION_SCALE() external view returns (uint256);

    function MAX_DATASTORE_DURATION() external view returns (uint8);

    function getDataStoreHashesForDurationAtTimestamp(uint8 duration, uint256 timestamp, uint32 index) external view returns(bytes32);
    
    function getNumDataStoresForDuration(uint8 duration) external view returns(uint32);

    function collateralToken() external view returns(IERC20);

    function dataLayrPaymentManager() external view returns(IDataLayrPaymentManager);
}
