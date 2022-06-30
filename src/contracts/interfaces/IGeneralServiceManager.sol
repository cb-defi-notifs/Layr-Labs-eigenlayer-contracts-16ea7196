// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IRepository.sol";
import "./ITaskMetadata.sol";

// TODO: provide more functions for this spec
interface IGeneralServiceManager {
	function repository() external view returns (IRepository);
	function getServiceObjectCreationTime(bytes32 serviceObjectHash) external view returns (uint256);
	function getServiceObjectExpiry(bytes32 serviceObjectHash) external view returns (uint256);
	function taskNumber() external returns (uint32);
	function taskMetadata() external returns (ITaskMetadata);
	function taskNumberToFee(uint32) external returns (uint256);
    function paymentFraudProofInterval() external returns (uint256);

    function paymentFraudProofCollateral() external returns (uint256);

    function getPaymentCollateral(address) external returns (uint256);

	function getTaskNumberSignatureHash(uint32) external returns (bytes32);

}