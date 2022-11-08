// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../contracts/interfaces/IServiceManager.sol";
import "../../contracts/middleware/Repository.sol";



contract MiddlewareRegistry{
    IRepository public immutable repository;


    constructor(
        Repository _repository
    ){
        repository = _repository;

    }

    function registerOperator(address operator) public {
        repository.serviceManager().recordFirstStakeUpdate(operator, 0);
    }

    function deregisterOperator(address operator) public {
        uint32 latestTime = repository.serviceManager().latestTime();
        repository.serviceManager().recordLastStakeUpdate(msg.sender, latestTime);
    }

    function propagateStakeUpdate(address operator, uint32 blockNumber, uint256 prevElement) external {
        uint32 serveUntil = repository.serviceManager().latestTime();
        repository.serviceManager().recordStakeUpdate(operator, blockNumber, serveUntil, prevElement);
    }

}