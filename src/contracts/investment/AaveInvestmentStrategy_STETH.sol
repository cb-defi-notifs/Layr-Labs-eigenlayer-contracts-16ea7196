// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./AaveInvestmentStrategy.sol";
import "./LIDO/IStableSwapStateOracle.sol";

//for use with AAVE's aSTETH product -- see https://etherscan.io/address/0x1982b2f5814301d4e9a8b0201555376e62f82428
//uses LIDO's StableSwapStateOracle for STETH/ETH ratio -- see https://docs.lido.fi/contracts/stable-swap-state-oracle
//the StableSwapStateOracle on Mainnet is here https://etherscan.io/address/0x3a6bd15abf19581e411621d669b6a2bbe741ffd6#readContract
contract AaveInvestmentStrategy_STETH is AaveInvestmentStrategy {
    IStableSwapStateOracle public stableSwapOracle;

    constructor(IInvestmentManager _investmentManager) 
        AaveInvestmentStrategy(_investmentManager)
    {}

    function initialize (IERC20 _underlyingToken, ILendingPool _lendingPool, IERC20 _aToken, IStableSwapStateOracle _stableSwapOracle
    ) initializer external {
        super.initialize(_underlyingToken, _lendingPool, _aToken);
        stableSwapOracle = _stableSwapOracle;
    }

    /**
     * @notice Used to convert a number of shares to the equivalent amount of underlying tokens for this strategy.
     *          This strategy uses LIDO's `stableSwapOracle` to estimate the conversion from stETH to ETH.
     * @notice In contrast to `sharesToUnderlying`, this function guarantees no state modifications
     * @param amountShares is the amount of shares to calculate its conversion into the underlying token
     * @dev Implementation for these functions in particular may vary signifcantly for different strategies
     */
    function sharesToUnderlyingView(uint256 amountShares) public view override returns(uint256) {
        (, , , uint256 exchangeRate) = stableSwapOracle.getState();
        return (super.sharesToUnderlyingView(amountShares) * exchangeRate) / 1e18;
    }

    /**
     * @notice Used to convert an amount of underlying tokens to the equivalent amount of shares in this strategy.
     *          This strategy uses LIDO's `stableSwapOracle` to estimate the conversion from ETH to stETH.
     * @notice In contrast to `underlyingToShares`, this function guarantees no state modifications
     * @param amountUnderlying is the amount of `underlyingToken` to calculate its conversion into strategy shares
     * @dev Implementation for these functions in particular may vary signifcantly for different strategies
     */
    function underlyingToSharesView(uint256 amountUnderlying)
        public
        view override
        returns (uint256)
    {
        (, , , uint256 exchangeRate) = stableSwapOracle.getState();
        return (super.underlyingToSharesView(amountUnderlying) * 1e18) / exchangeRate;
    }
}
