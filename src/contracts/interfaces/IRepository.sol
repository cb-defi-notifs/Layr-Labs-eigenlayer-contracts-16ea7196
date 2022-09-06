// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "./IServiceManager.sol";
import "./IVoteWeigher.sol";
import "./IRegistry.sol";


/**
 @notice This is the interface for Repository contract.
 */



interface IRepository {

    /// @notice returns voteWeigher contract for the middleware 
    function voteWeigher() external view returns (IVoteWeigher);

    /// @notice returns serviceManager contract for the middleware 
    function serviceManager() external view returns (IServiceManager);

    /// @notice returns registry contract for the middleware     
    function registry() external view returns (IRegistry);

    /// @notice returns owner of the middleware  
    function owner() external view returns (address);
}
