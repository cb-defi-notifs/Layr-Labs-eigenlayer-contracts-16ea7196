// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../contracts/interfaces/IServiceManager.sol";
import "../../contracts/interfaces/IRegistry.sol";

import "../../contracts/middleware/Repository.sol";

import "forge-std/Test.sol";




contract MiddlewareRegistry is IRegistry, DSTest{
    IRepository public immutable repository;


    constructor(
        Repository _repository
    ){
        repository = _repository;

    }

    function registerOperator(address operator, uint32 serveUntil) public {

        repository.serviceManager().recordFirstStakeUpdate(operator, serveUntil);
    }

    function deregisterOperator(address operator) public {
        uint32 latestTime = repository.serviceManager().latestTime();
        repository.serviceManager().recordLastStakeUpdate(operator, latestTime);
    }

    function propagateStakeUpdate(address operator, uint32 blockNumber, uint256 prevElement) external {
        uint32 serveUntil = repository.serviceManager().latestTime();
        repository.serviceManager().recordStakeUpdate(operator, blockNumber, serveUntil, prevElement);
    }

     function isActiveOperator(address operator) external pure returns (bool) {
        if (operator != address(0)){
            return true;
        } else {
            return false;
        }
     }

}