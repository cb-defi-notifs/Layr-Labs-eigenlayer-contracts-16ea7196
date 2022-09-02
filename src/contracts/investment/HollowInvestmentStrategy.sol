// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "./InvestmentStrategyBase.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

/**
 * This contract may be used in a case where the underlying asset is actually non-transferrable/immaterial.
*/

contract HollowInvestmentStrategy is
    InvestmentStrategyBase
{

    constructor(IInvestmentManager _investmentManager) 
        InvestmentStrategyBase(_investmentManager)
    {}

    function deposit(IERC20 token, uint256 amount)
        external override
        onlyInvestmentManager
        returns (uint256 newShares)
    {
        require(token == IERC20(address(0)), "HollowInvestmentStrategy.deposit: Must pass in 0 token to make sure not actually sending tokens");
        totalShares += amount;
        return amount;
    }

    function withdraw(
        address,
        IERC20,
        uint256 shareAmount
    ) external override onlyInvestmentManager {
        totalShares -= shareAmount;
    }

    function explanation() external pure override returns (string memory) {
        return "An investment strategy for tracking tokens that are not ERC20s";
    }

    function sharesToUnderlyingView(uint256 amountShares)
        public
        pure override
        returns (uint256)
    {
        return amountShares;
    }

    function underlyingToSharesView(uint256 amountUnderlying)
        public
        pure override
        returns (uint256)
    {
        return amountUnderlying;
    }
}
