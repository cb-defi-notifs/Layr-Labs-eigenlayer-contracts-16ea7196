// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IServiceManager.sol";
import "./IVoteWeigher.sol";
import "./IRegistry.sol";

interface IRepository {
    function voteWeigher() external view returns (IVoteWeigher);

    function serviceManager() external view returns (IServiceManager);

    function registry() external view returns (IRegistry);

    function owner() external view returns (address);
}
