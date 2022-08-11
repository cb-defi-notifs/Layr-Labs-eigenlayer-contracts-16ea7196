// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IRepositoryAccess.sol";
// import "./ITaskMetadata.sol";
import "./IEigenLayrDelegation.sol";

// TODO: provide more functions for this spec
interface IServiceManager is IRepositoryAccess {

    function taskNumber() external view returns (uint32);

    // function taskMetadata() external view returns (ITaskMetadata);

    function taskNumberToFee(uint32) external view returns (uint256);

    function freezeOperator(address operator) external;

    // function paymentFraudProofInterval() external view returns (uint256);

    // function paymentFraudProofCollateral() external view returns (uint256);

    // function getPaymentCollateral(address) external view returns (uint256);

    // function getTaskNumberSignatureHash(uint32) external view returns (bytes32);

    function collateralToken() external view returns(IERC20);

    function eigenLayrDelegation() external view returns(IEigenLayrDelegation);

    function stakeWithdrawalVerification(bytes calldata data, uint256 initTimestamp, uint256 unlockTime) external;

    function latestTime() external view returns(uint32);
}
