// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../../contracts/interfaces/IServiceManager.sol";

contract ServiceManagerMock is IServiceManager {

    /// @notice Returns the current 'taskNumber' for the middleware
    function taskNumber() external pure returns (uint32) {
        return 0;
    }

    /// @notice Permissioned function that causes the ServiceManager to freeze the operator on EigenLayer, through a call to the Slasher contract
    function freezeOperator(address operator) external pure {}

    /// @notice Permissioned function that causes the ServiceManager to revoke its ability to slash the operator on EigenLayer, through a call to the Slasher contract
    function revokeSlashingAbility(address operator, uint32 unbondedAfter) external pure {}

    /// @notice Permissioned function to have the ServiceManager forward a call to the slasher, recording an initial stake update (on operator registration)
    function recordFirstStakeUpdate(address operator, uint32 serveUntil) external pure {}

    /// @notice Permissioned function to have the ServiceManager forward a call to the slasher, recording a stake update
    function recordStakeUpdate(address operator, uint32 updateBlock, uint32 serveUntil, uint256 prevElement) external pure {}

    /// @notice Permissioned function to have the ServiceManager forward a call to the slasher, recording a final stake update (on operator deregistration)
    function recordLastStakeUpdate(address operator, uint32 serveUntil) external pure {}

    /// @notice Collateral token used for placing collateral on challenges & payment commits
    function collateralToken() external pure returns (IERC20) {
        return IERC20(address(0));
    }

    /// @notice The Delegation contract of EigenLayer.
    function eigenLayrDelegation() external pure returns (IEigenLayrDelegation) {
        return IEigenLayrDelegation(address(0));
    }

    /// @notice Returns the `latestTime` until which operators must serve.
    function latestTime() external pure returns (uint32) {
        return type(uint32).max;
    }

    function owner() external pure returns (address) {
        return address(0);
    }
}
