// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDataLayrServiceManager {
    function dumpNumber() external returns (uint32);

    function getDumpNumberFee(uint32) external returns (uint256);

    function getDumpNumberSignatureHash(uint32) external returns (bytes32);

    function resolvePaymentChallenge(address, bool) external;

    function paymentFraudProofInterval() external returns (uint256);

    function paymentFraudProofCollateral() external returns (uint256);

    function getPaymentCollateral(address) external returns (uint256);

    function resolveDisclosureChallenge(bytes32, address, bool) external;

    function disclosureFraudProofInterval() external returns (uint256);

    function powersOfTauMerkleRoot() external returns(bytes32);
    function numPowersOfTau() external returns(uint48);
    function log2NumPowersOfTau() external returns(uint48);
    
    function getPolyHash(address, bytes32) external returns(bytes32);
}