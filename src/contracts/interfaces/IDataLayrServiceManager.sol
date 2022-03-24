// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDataLayrServiceManager {
    function dumpNumber() external returns (uint48);

    function getDumpNumberFee(uint48) external returns (uint256);

    function getDumpNumberSignatureHash(uint48) external returns (bytes32);

    function resolvePaymentChallenge(address, bool) external;

    function paymentFraudProofInterval() external returns (uint256);

    function paymentFraudProofCollateral() external returns (uint256);

    function getPaymentCollateral(address) external returns (uint256);
}