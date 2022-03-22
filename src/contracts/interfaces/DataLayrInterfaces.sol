// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IQueryManager.sol";

/**
 * @title DataLayr
 * @dev L1 contracts that handles DataLayr Node registration
 *
 */

interface IDataLayr {
    function initDataStore(
        uint64 dumpNumber,
        bytes32 ferkleRoot,
        uint32 totalBytes,
        uint32 storePeriodLength,
        address submitter
    ) external;

    function confirm(
        uint256 dumpNumber,
        bytes32 ferkleRoot,
        address submitter,
        uint256 totalEthSigned,
        uint256 totalEigenSigned
    ) external;
}

interface IDataLayrVoteWeigher {
    function setLatestTime(uint32) external;

    function getOperatorId(address) external returns (uint32);

    function getOperatorFromDumpNumber(address) external view returns (uint48);
}

interface IDataLayrServiceManager {
    function dumpNumber() external returns (uint48);

    function getDumpNumberFee(uint48) external returns (uint256);

    function getDumpNumberSignatureHash(uint48) external returns (bytes32);

    function resolvePaymentChallenge(address, bool) external;

    function paymentFraudProofInterval() external returns (uint256);

    function paymentFraudProofCollateral() external returns (uint256);

    function getPaymentCollateral(address) external returns (uint256);
}
