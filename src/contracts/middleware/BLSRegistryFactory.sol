// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./BLSRegistry.sol";

/**
 * @notice This factory contract is used for launching new repository contracts.
 */


contract BLSRegistryFactory {
    function createNewBLSRegistry(
        IRepository repository,
        IEigenLayrDelegation delegation,
        IInvestmentManager investmentManager,
        BLSRegistry.StrategyAndWeightingMultiplier[] memory _ethStrategiesConsideredAndMultipliers,
        BLSRegistry.StrategyAndWeightingMultiplier[] memory _eigenStrategiesConsideredAndMultipliers
    ) external returns(IRegistry) {
        BLSRegistry registry = new BLSRegistry(Repository(address(repository)), delegation, investmentManager, _ethStrategiesConsideredAndMultipliers, _eigenStrategiesConsideredAndMultipliers);
        return (registry);
    }
}
