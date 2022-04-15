// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../governance/Timelock.sol";
import "../interfaces/ITimelock_Managed.sol";

//note that this contract does not initialize the timelock itself. an inheriting contract should use _transferTimelock in its constructor/initializer
abstract contract Timelock_Managed is ITimelock_Managed {
    /// @notice The address of the Protocol Timelock
    Timelock public timelock;
    
    modifier onlyTimelock() {
        require(msg.sender == address(timelock), "onlyTimelock");
        _;
    }

    /// @notice Emitted when the 'timelock' address has been changed
    event TimelockTransferred(address indexed previousAddress, address indexed newAddress);

    function setTimelock(Timelock _timelock) external onlyTimelock {
        _setTimelock(_timelock);
    }

    function _setTimelock(Timelock _timelock) internal {
        emit TimelockTransferred(address(timelock), address(_timelock));
        timelock = _timelock;
    }
}