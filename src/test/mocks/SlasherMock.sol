// //SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../../contracts/interfaces/ISlasher.sol";


contract SlasherMock is ISlasher, Test {

    mapping(address => bool) public isFrozen;
    bool public _canWithdraw = true;

    function setCanWithdrawResponse(bool response) external {
        _canWithdraw = response;
    }

    function setOperatorFrozenStatus(address operator, bool status) external{
        isFrozen[operator] = status;
    }

    function freezeOperator(address toBeFrozen) external {
        isFrozen[toBeFrozen] = true;
    }
    
    function optIntoSlashing(address contractAddress) external{}

    function resetFrozenStatus(address[] calldata frozenAddresses) external{}

    function recordFirstStakeUpdate(address operator, uint32 serveUntil) external{}

    function recordStakeUpdate(address operator, uint32 updateBlock, uint32 serveUntil, uint256 insertAfter) external{}

    function recordLastStakeUpdateAndRevokeSlashingAbility(address operator, uint32 serveUntil) external{}

    /// @notice Returns true if `slashingContract` is currently allowed to slash `toBeSlashed`.
    function canSlash(address toBeSlashed, address slashingContract) external view returns (bool){}

    /// @notice Returns the UTC timestamp until which `serviceContract` is allowed to slash the `operator`.
    function bondedUntil(address operator, address serviceContract) external view returns (uint32){}

    /// @notice Returns the block at which the `serviceContract` last updated its view of the `operator`'s stake
    function latestUpdateBlock(address operator, address serviceContract) external view returns (uint32){}

    /// @notice A search routine for finding the correct input value of `insertAfter` to `recordStakeUpdate` / `_updateMiddlewareList`.
    function getCorrectValueForInsertAfter(address operator, uint32 updateBlock) external view returns (uint256){}

    function canWithdraw(address /*operator*/, uint32 /*withdrawalStartBlock*/, uint256 /*middlewareTimesIndex*/) external view returns(bool) {
        return _canWithdraw;
    }

    /// @notice Getter function for fetching `operatorToMiddlewareTimes[operator][index].stalestUpdateBlock`.
    function getMiddlewareTimesIndexBlock(address operator, uint32 index) external view returns(uint32){}

    /// @notice Getter function for fetching `operatorToMiddlewareTimes[operator][index].latestServeUntil`.
    function getMiddlewareTimesIndexServeUntil(address operator, uint32 index) external view returns(uint32){}


}