// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./IDataLayr.sol";

interface IDataLayrServiceManager {
    struct SignatoryRecordMinusDumpNumber {
        bytes32[] nonSignerPubkeyHashes;
        uint256 totalEthStakeSigned;
        uint256 totalEigenStakeSigned;
    }
    function dumpNumber() external returns (uint32);

    function dumpNumberToFee(uint32) external returns (uint256);

    function getDumpNumberSignatureHash(uint32) external returns (bytes32);

    function resolvePaymentChallenge(address, bool) external;

    function paymentFraudProofInterval() external returns (uint256);

    function paymentFraudProofCollateral() external returns (uint256);

    function getPaymentCollateral(address) external returns (uint256);


    function resolveLowDegreeChallenge(bytes32 headerHash, address operator, uint32 commitTime) external;

    function numPowersOfTau() external returns(uint48);
    function log2NumPowersOfTau() external returns(uint48);
    
    function dataLayr() external view returns(IDataLayr);
}