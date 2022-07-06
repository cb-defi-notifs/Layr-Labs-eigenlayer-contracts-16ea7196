// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IDataLayr.sol";
import "./IServiceManager.sol";

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

    function dataStoreId() external returns (uint32);

    function dataStoreIdToFee(uint32) external returns (uint96);

    function getDataStoreIdSignatureHash(uint32) external view returns (bytes32);

    //function resolvePaymentChallenge(address, bool) external;

    function paymentFraudProofInterval() external returns (uint256);

    function paymentFraudProofCollateral() external returns (uint256);

    function getPaymentCollateral(address) external returns (uint256);

    function slashOperator(address operator) external;

    function latestTime() external returns(uint32);

    function numPowersOfTau() external returns(uint48);
    function log2NumPowersOfTau() external returns(uint48);
    
    function dataLayr() external view returns(IDataLayr);

    function DURATION_SCALE() external view returns(uint256);
    function MAX_DATASTORE_DURATION() external view returns(uint8);

    function getDataStoreIdsForDuration(uint8 duration, uint256 timestamp) external view returns(bytes32);
    
    function totalDataStoresForDuration(uint8 duration) external view returns(uint32);

    function collateralToken() external view returns(IERC20);
    
    function depositFutureFees(address onBehalfOf, uint256 amount) external;
}