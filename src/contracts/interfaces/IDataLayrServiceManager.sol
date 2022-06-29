// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./IDataLayr.sol";

interface IDataLayrServiceManager {
    struct DataStoreIdPair {
        uint32 durationDataStoreId;
        uint32 globalDataStoreId;
    }

    struct SignatoryRecordMinusDumpNumber {
        bytes32[] nonSignerPubkeyHashes;
        uint256 totalEthStakeSigned;
        uint256 totalEigenStakeSigned;
    }

    function dumpNumber() external returns (uint32);

    function dumpNumberToFee(uint32) external returns (uint256);

    function getDumpNumberSignatureHash(uint32) external returns (bytes32);

    //function resolvePaymentChallenge(address, bool) external;

    function paymentFraudProofInterval() external returns (uint256);

    function paymentFraudProofCollateral() external returns (uint256);

    function getPaymentCollateral(address) external returns (uint256);

    function resolveLowDegreeChallenge(bytes32 headerHash, address operator, uint32 commitTime) external;

    function numPowersOfTau() external returns(uint48);
    function log2NumPowersOfTau() external returns(uint48);
    
    function dataLayr() external view returns(IDataLayr);

    function DURATION_SCALE() external view returns(uint256);
    function MAX_DATASTORE_DURATION() external view returns(uint8);

    function firstDataStoreIdAtTimestampForDuration(uint8 duration, uint256 timestamp) external view returns(DataStoreIdPair memory);

    function lastDataStoreIdAtTimestampForDuration(uint8 duration, uint256 timestamp) external view returns(DataStoreIdPair memory);

    function getDataStoreIdsForDuration(uint8 duration, uint256 timestamp, uint256 bombDataStoreIndex) external view returns(DataStoreIdPair memory);
    
    function totalDataStoresForDuration(uint8 duration) external view returns(uint32);
}