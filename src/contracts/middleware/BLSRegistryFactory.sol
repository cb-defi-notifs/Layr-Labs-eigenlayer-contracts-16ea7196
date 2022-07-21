// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./BLSRegistry.sol";

/**
 * @notice Any new middleware launching on EigenLayr would be calling createNewBLSRegistry 
           for spawning BLSRegistry contract.  
 */

contract BLSRegistryFactory {

    
    /**
     @param repository is the respositry that specifies some other contracts deployed by the middleware,
     @param delegation is the delegation contract deployed as part of EigenLayr,
     @param investmentManager is the contract for managing investment in different strategies; deployed 
                              only once as part of EigenLayr,
     @param _ethStrategiesConsideredAndMultipliers is the weights given by the middleware, based on its 
                                                   discretion, to different modalities of ETH staked 
                                                   with EigenLayr,
     @param _eigenStrategiesConsideredAndMultipliers is the weights given by the middleware, based on its 
                                                     discretion, to different modalities of EIGEN staked 
                                                     with EigenLayr,   
     */
    /**
     @dev (1) In order to leverage trust from EigenLayr, middlewares are recommended to specify 
              delegation and investmentManager contracts that have been deployed as part of EigenLayr.
          (2) Middlewares can specify their own repository contract and weightage vectors based 
              on their own discretion.     
     */
    function createNewBLSRegistry(
        IRepository repository,
        IEigenLayrDelegation delegation,
        IInvestmentManager investmentManager,
        BLSRegistry.StrategyAndWeightingMultiplier[] memory _ethStrategiesConsideredAndMultipliers,
        BLSRegistry.StrategyAndWeightingMultiplier[] memory _eigenStrategiesConsideredAndMultipliers
    ) external returns(IRegistry) {

        // spawns a new BLSRegistry contract.
        BLSRegistry registry = new BLSRegistry(Repository(address(repository)), delegation, investmentManager, _ethStrategiesConsideredAndMultipliers, _eigenStrategiesConsideredAndMultipliers);
        
        return (registry);
    }
}
