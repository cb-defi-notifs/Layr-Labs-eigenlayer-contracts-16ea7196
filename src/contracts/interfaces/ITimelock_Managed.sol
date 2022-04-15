// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../governance/Timelock.sol";

interface ITimelock_Managed {
    function timelock() external view returns (Timelock);
}