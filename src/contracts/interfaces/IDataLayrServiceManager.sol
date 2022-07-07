// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IDataLayr.sol";
import "./IServiceManager.sol";
import "./IEigenLayrDelegation.sol";

interface IDataLayrServiceManager is IServiceManager {
    struct DataStoreMetadata {
        uint32 durationDataStoreId;
        uint32 globalDataStoreId;
        uint96 fee;
    }

    struct DataStoreSearchData {
        uint8 duration;
        uint256 timestamp;
        uint256 index;
        DataStoreMetadata[] metadatas;
    }

    struct SignatoryRecordMinusDataStoreId {
        bytes32[] nonSignerPubkeyHashes;
        uint256 totalEthStakeSigned;
        uint256 totalEigenStakeSigned;
    }

    function dataStoreId() external view returns (uint32);

    function dataStoreIdToFee(uint32) external view returns (uint96);

    function getDataStoreIdSignatureHash(uint32) external view returns (bytes32);

    function slashOperator(address operator) external;

    function latestTime() external view returns(uint32);

    function numPowersOfTau() external view returns(uint48);

    function log2NumPowersOfTau() external view returns(uint48);
    
    function dataLayr() external view returns(IDataLayr);

    function DURATION_SCALE() external view returns(uint256);

    function MAX_DATASTORE_DURATION() external view returns(uint8);

    function getDataStoreIdsForDuration(uint8 duration, uint256 timestamp) external view returns(bytes32);
    
    function totalDataStoresForDuration(uint8 duration) external view returns(uint32);

    function eigenLayrDelegation() external view returns(IEigenLayrDelegation);

    function collateralToken() external view returns(IERC20);
}