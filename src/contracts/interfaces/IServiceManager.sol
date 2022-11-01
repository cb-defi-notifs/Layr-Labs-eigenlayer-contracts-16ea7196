// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IRepositoryAccess.sol";
import "./IEigenLayrDelegation.sol";

/**
 * @title Interface for a `ServiceManager`-type contract.
 * @author Layr Labs, Inc.
 */
// TODO: provide more functions for this spec
interface IServiceManager  {
    
    function taskNumber() external view returns (uint32);

    function freezeOperator(address operator) external;

    function revokeSlashingAbility(address operator, uint32 unbondedAfter) external;

    function recordFirstStakeUpdate(address operator, uint32 serveUntil) external;

    function recordStakeUpdate(address operator, uint32 updateBlock, uint32 serveUntil, uint256 prevElement) external;

    function recordLastStakeUpdate(address operator, uint32 serveUntil) external;

    function collateralToken() external view returns (IERC20);

    function eigenLayrDelegation() external view returns (IEigenLayrDelegation);

    function stakeWithdrawalVerification(bytes calldata data, uint256 initTimestamp, uint256 unlockTime)
        external
        view;

    function latestTime() external view returns (uint32);
}