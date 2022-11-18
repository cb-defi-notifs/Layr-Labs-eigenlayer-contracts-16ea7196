// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../contracts/interfaces/IServiceManager.sol";
import "../../contracts/interfaces/IRegistry.sol";
import "../../contracts/interfaces/IInvestmentManager.sol";
import "../../contracts/interfaces/IEphemeralKeyRegistry.sol";


import "forge-std/Test.sol";




contract EigenDARegistry is IRegistry, DSTest{
    IServiceManager public serviceManager;
    IInvestmentManager public investmentManager;
    IEphemeralKeyRegistry public immutable ephemeralKeyRegistry;


    constructor(
        IServiceManager _serviceManager,
        IInvestmentManager _investmentManager,
        IEphemeralKeyRegistry _ephemeralKeyRegistry
    ){
        serviceManager = _serviceManager;
        investmentManager = _investmentManager;
        ephemeralKeyRegistry = _ephemeralKeyRegistry;

    }

    function registerOperator(address operator, uint32 serveUntil) public {        
        require(investmentManager.slasher().canSlash(operator, address(serviceManager)), "Not opted into slashing");
        serviceManager.recordFirstStakeUpdate(operator, serveUntil);
        ephemeralKeyRegistry.postFirstEphemeralKeyHashes(msg.sender, ephemeralKeyHash1, ephemeralKeyHash2);


    }

    function deregisterOperator(address operator) public {
        uint32 latestTime = serviceManager.latestTime();
        serviceManager.recordLastStakeUpdate(operator, latestTime);
        ephemeralKeyRegistry.revealLastEphemeralKeys(msg.sender, startIndex, ephemeralKeys);

    }

    function propagateStakeUpdate(address operator, uint32 blockNumber, uint256 prevElement) external {
        uint32 serveUntil = serviceManager.latestTime();
        serviceManager.recordStakeUpdate(operator, blockNumber, serveUntil, prevElement);
    }

     function isActiveOperator(address operator) external pure returns (bool) {
        if (operator != address(0)){
            return true;
        } else {
            return false;
        }
     }

}