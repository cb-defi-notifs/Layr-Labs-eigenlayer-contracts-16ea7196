// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/**
 @notice This is the interface for Repository contract.
 */
interface IRepository {

    /// @notice returns voteWeigher contract for the middleware 
    function voteWeigher() external view returns (address);

    /// @notice returns serviceManager contract for the middleware 
    function serviceManager() external view returns (address);

    /// @notice returns registry contract for the middleware     
    function registry() external view returns (address);

    /// @notice returns owner of the middleware  
    function owner() external view returns (address);
}
