// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IRegistry.sol";

interface IDataLayrRegistry is IRegistry {
// TODO: decide if this struct is better defined in 'IRegistry', 'IDataLayrRegistry', or a separate file
/*
    struct OperatorStake {
        uint32 updateBlockNumber;
        uint32 nextUpdateBlockNumber;
        uint96 ethStake;
        uint96 eigenStake;
    }
*/
    // function setLatestTime(uint32 _latestTime) external;
}
