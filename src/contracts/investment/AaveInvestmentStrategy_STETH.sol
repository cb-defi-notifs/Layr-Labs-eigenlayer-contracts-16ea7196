// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./AaveInvestmentStrategy.sol";
import "./LIDO/IStableSwapStateOracle.sol";

//for use with AAVE's aSTETH product -- see https://etherscan.io/address/0x1982b2f5814301d4e9a8b0201555376e62f82428
//uses LIDO's StableSwapStateOracle for STETH/ETH ratio -- see https://docs.lido.fi/contracts/stable-swap-state-oracle
//the StableSwapStateOracle on Mainnet is here https://etherscan.io/address/0x3a6bd15abf19581e411621d669b6a2bbe741ffd6#readContract
contract AaveInvestmentStrategy_STETH is AaveInvestmentStrategy {
    IStableSwapStateOracle public stableSwapOracle;

    function initialize (ILendingPool _lendingPool, IERC20 _underlyingToken, IERC20 _aToken, address _investmentManager, IStableSwapStateOracle _stableSwapOracle
    ) initializer external {
        stableSwapOracle = _stableSwapOracle;
        super.initialize(_lendingPool, _underlyingToken, _aToken, _investmentManager);
    }

    function sharesToUnderlying(uint256 numShares) public view override returns(uint256) {
        (, , , uint256 exchangeRate) = stableSwapOracle.getState();
        return (sharesToUnderlying(numShares) * exchangeRate) / 1e18;
    }

    function sharesToUnderlyingView(uint256 numShares) public view override returns(uint256) {
        (, , , uint256 exchangeRate) = stableSwapOracle.getState();
        return (sharesToUnderlyingView(numShares) * exchangeRate) / 1e18;
    }
}
