// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IInvestmentStrategy.sol";
import "../interfaces/IInvestmentManager.sol";
import "../permissions/RepositoryAccess.sol";


/**
 @notice This is the contract for specifying all storage variables of VoteWeigherBase.sol
 */

abstract contract VoteWeigherBaseStorage is RepositoryAccess {

    /** 
     @notice In weighting a particular investment strategy, underlying asset for that strategy is 
             multiplied by its multiplier then divided by WEIGHTING_DIVISOR
     */
    struct StrategyAndWeightingMultiplier {
        IInvestmentStrategy strategy;
        uint96 multiplier;
    }


    /** 
     @notice mapping from quorum number to the list of strategies considered and their 
             corresponding weights for that specific quorum
     */
    mapping(uint256 => StrategyAndWeightingMultiplier[]) public strategiesConsideredAndMultipliers;


    uint256 internal constant WEIGHTING_DIVISOR = 1e18;


    IEigenLayrDelegation public immutable delegation;
    IInvestmentManager public immutable investmentManager;


    constructor(IRepository _repository, IEigenLayrDelegation _delegation, IInvestmentManager _investmentManager)
        RepositoryAccess(_repository)
    {
        delegation = _delegation;
        investmentManager = _investmentManager;
    }
}