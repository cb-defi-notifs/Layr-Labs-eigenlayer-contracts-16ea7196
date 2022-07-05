// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IInvestmentStrategy.sol";
import "../interfaces/IInvestmentManager.sol";
import "../permissions/RepositoryAccess.sol";

abstract contract VoteWeigherBaseStorage is RepositoryAccess {
    // in weighting a set of strategies, underlying asset in for each strategy is multiplied by its multiplier then divided by WEIGHTING_DIVISOR
    struct StrategyAndWeightingMultiplier {
        IInvestmentStrategy strategy;
        uint96 multiplier;
    }

    uint256 internal constant WEIGHTING_DIVISOR = 1e18;
    IEigenLayrDelegation public immutable delegation;
    IInvestmentManager public immutable investmentManager;

    // quorum number => list of strategies considered and weights (for specified quorum)
    mapping(uint256 => StrategyAndWeightingMultiplier[]) public strategiesConsideredAndMultipliers;
    constructor(IRepository _repository, IEigenLayrDelegation _delegation, IInvestmentManager _investmentManager)
        RepositoryAccess(_repository)
    {
        delegation = _delegation;
        investmentManager = _investmentManager;
    }
}