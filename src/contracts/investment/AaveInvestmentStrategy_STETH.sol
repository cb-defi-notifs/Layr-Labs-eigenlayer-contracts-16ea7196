// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./AaveInvestmentStrategy.sol";
import "./LIDO/IStableSwapStateOracle.sol";

//for use with AAVE's aSTETH product -- see https://etherscan.io/address/0x1982b2f5814301d4e9a8b0201555376e62f82428
//uses LIDO's StableSwapStateOracle for STETH/ETH ratio -- see https://docs.lido.fi/contracts/stable-swap-state-oracle
//the StableSwapStateOracle on Mainnet is here https://etherscan.io/address/0x3a6bd15abf19581e411621d669b6a2bbe741ffd6#readContract
contract AaveInvestmentStrategy_STETH is AaveInvestmentStrategy {
    IStableSwapStateOracle public stableSwapOracle;

    function initialize (address _investmentManager, IERC20 _underlyingToken, ILendingPool _lendingPool, IERC20 _aToken, IStableSwapStateOracle _stableSwapOracle
    ) initializer external {
        super.initialize(_investmentManager, _underlyingToken, _lendingPool, _aToken);
        stableSwapOracle = _stableSwapOracle;
    }

    function sharesToUnderlyingView(uint256 numShares) public view override returns(uint256) {
        (, , , uint256 exchangeRate) = stableSwapOracle.getState();
        return (sharesToUnderlyingView(numShares) * exchangeRate) / 1e18;
    }
}
