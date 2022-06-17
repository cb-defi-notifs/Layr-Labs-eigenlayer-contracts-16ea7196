// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IRepository.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IInvestmentStrategy.sol";
import "../interfaces/IInvestmentManager.sol";

abstract contract VoteWeigherBaseStorage {
    // in weighting a set of strategies, underlying asset in for each strategy is multiplied by its multiplier then divided by WEIGHTING_DIVISOR
    struct StrategyAndWeightingMultiplier {
        IInvestmentStrategy strategy;
        uint96 multiplier;
    }

    uint256 internal constant WEIGHTING_DIVISOR = 1e18;
    IRepository public immutable repository;
    IEigenLayrDelegation public immutable delegation;
    IInvestmentManager public immutable investmentManager;

    // quorum number => list of strategies considered and weights (for specified quorum)
    mapping(uint256 => StrategyAndWeightingMultiplier[]) public strategiesConsideredAndMultipliers;
    constructor(IRepository _repository, IEigenLayrDelegation _delegation, IInvestmentManager _investmentManager) {
        repository = _repository;
        delegation = _delegation;
        investmentManager = _investmentManager;
    }
}