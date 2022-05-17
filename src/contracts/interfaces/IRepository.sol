// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IServiceManager.sol";
import "./IVoteWeigher.sol";
import "./IRegistrationManager.sol";
import "../interfaces/ITimelock_Managed.sol";

interface IRepository is ITimelock_Managed {
    function voteWeigher() external view returns (IVoteWeigher);

    function serviceManager() external view returns (IServiceManager);

    function registrationManager() external view returns (IRegistrationManager);
}
