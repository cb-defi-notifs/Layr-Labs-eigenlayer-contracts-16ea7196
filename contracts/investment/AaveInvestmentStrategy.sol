// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/InvestmentInterfaces.sol";
import "../interfaces/IERC20.sol";
import "./aave/ILendingPool.sol";

contract AaveInvestmentStrategy is IInvestmentStrategy {
    ILendingPool public lendingPool;
    IERC20 public token;
    IERC20 public aToken;
    address public governor;
    address public investmentManager;
    uint256 public totalShares;

    constructor(ILendingPool _lendingPool, IERC20 _token, IERC20 _aToken, address _investmentManager) {
        lendingPool = _lendingPool;
        token = _token;
        aToken = _aToken;
        governor = msg.sender;
        investmentManager = _investmentManager;
    }

    function deposit(
        address depositer,
        IERC20[] calldata tokens,
        uint256[] calldata amounts
    ) external returns (uint256) {
        require(msg.sender == investmentManager, "Only the investment manager can deposit into this strategy");
        require(1 == amounts.length && tokens.length == 1, "Can only deposit 1 token to this contract");
        require(token == tokens[0], "Can only deposit this strategy's token");
        //deposit and the "shares" are in proportion to the new aTokens minted
        uint256 aTokensBefore = aToken.balanceOf(address(this));
        token.transferFrom(depositer, address(this), amounts[0]);
        lendingPool.deposit(
            address(token),
            amounts[0],
            address(this),
            0
        );
        uint256 aTokenIncrease = aToken.balanceOf(address(this)) - aTokensBefore;
        uint256 newShares;
        if (totalShares == 0) {
            newShares = aTokenIncrease;
        } else {
            newShares = (aTokenIncrease * totalShares) / aTokensBefore;
        }
        totalShares += newShares;
        return newShares;
    }

    function depositSingle(
        address depositer,
        IERC20 depositToken,
        uint256 amount
    ) external returns (uint256) {
        require(msg.sender == investmentManager, "Only the investment manager can deposit into this strategy");
        require(token == depositToken, "Can only deposit this strategy's token");
        //deposit and the "shares" are the new aTokens minted
        uint256 aTokensBefore = aToken.balanceOf(address(this));
        token.transferFrom(depositer, address(this), amount);
        lendingPool.deposit(
            address(token),
            amount,
            address(this),
            0
        );
        uint256 aTokenIncrease = aToken.balanceOf(address(this)) - aTokensBefore;
        uint256 newShares;
        if (totalShares == 0) {
            newShares = aTokenIncrease;
        } else {
            newShares = (aTokenIncrease * totalShares) / aTokensBefore;
        }
        totalShares += newShares;
        return newShares;
    }

    function withdraw(
        address depositer,
        IERC20[] calldata tokens,
        uint256[] calldata amounts
    ) external returns(uint256) {
        require(msg.sender == investmentManager, "Only the investment manager can deposit into this strategy");
        require(1 == amounts.length && tokens.length == 1, "Can only deposit 1 token to this contract");
        require(token == tokens[0], "Can only deposit this strategy's token");
        //withdraw from lendingPool
        uint256 toWithdraw = sharesToUnderlying(amounts[0]);
        uint256 amountWithdrawn = lendingPool.withdraw(
            address(token),
            toWithdraw,
            depositer
        );
        totalShares -= amounts[0];
        return amountWithdrawn;
    }

    function explanation() external pure returns (string memory) {
        return "A simple investment strategy that allows a single asset to be deposited and loans it out on Aave";
    }

    function updateAToken(IERC20 _aToken) external {
        require(governor == msg.sender, "Only governor can change the aToken");
        aToken = _aToken;
    }

    function underlyingEthValueOfShares(uint256 numShares) public view returns(uint256) {
        return sharesToUnderlying(numShares);
    }

    function underlyingEthValueOfSharesView(uint256 numShares) public view returns(uint256) {
        return sharesToUnderlyingView(numShares);
    }

    function sharesToUnderlyingView(uint256 amountShares) public view returns(uint256) {
        if (totalShares == 0) {
            return 0;
        } else {
            return (aToken.balanceOf(address(this)) * amountShares) / totalShares;
        }
    }
    function sharesToUnderlying(uint256 amountShares) public view returns(uint256) {
        if (totalShares == 0) {
            return 0;
        } else {
            return (aToken.balanceOf(address(this)) * amountShares) / totalShares;
        }
    }
    function underlyingToSharesView(uint256 amountUnderlying) public view returns(uint256) {
        if (totalShares == 0) {
            return amountUnderlying;
        } else {
            return (amountUnderlying * totalShares) / aToken.balanceOf(address(this));
        }
    }
    function underlyingToShares(uint256 amountUnderlying) public view returns(uint256) {
        if (totalShares == 0) {
            return amountUnderlying;
        } else {
            return (amountUnderlying * totalShares) / aToken.balanceOf(address(this));
        }
    }
    function userUnderlying(address user) public returns(uint256) {
        return sharesToUnderlying(shares(user));
    }
    function userUnderlyingView(address user) public view returns(uint256) {
        return sharesToUnderlyingView(shares(user));
    }
    function shares(address user) public view returns(uint256) {
        return IInvestmentManager(investmentManager).investorStratShares(user, IInvestmentStrategy(address(this)));
    }
}
