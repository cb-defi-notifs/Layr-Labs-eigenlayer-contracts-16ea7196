// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/InvestmentInterfaces.sol";
import "../interfaces/IERC20.sol";
import "./aave/ILendingPool.sol";

contract AaveInvestmentStrategy is IInvestmentStrategy {
    ILendingPool public lendingPool;
    IERC20 public token;
    IERC20 public aToken;
    address governer;
    address investmentManager;

    constructor(ILendingPool _lendingPool, IERC20 _token, IERC20 _aToken, address _investmentManager) {
        lendingPool = _lendingPool;
        token = _token;
        aToken = _aToken;
        governer = msg.sender;
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
        //deposit and the "shares" are the new aTokens minted
        uint256 aTokenIncrease = aToken.balanceOf(address(this));
        token.transferFrom(depositer, address(this), amounts[0]);
        lendingPool.deposit(
            address(token),
            amounts[0],
            address(this),
            0
        );
        aTokenIncrease = aToken.balanceOf(address(this)) - aTokenIncrease;
        return aTokenIncrease;
    }

    function depositSingle(
        address depositer,
        IERC20 depositToken,
        uint256 amount
    ) external returns (uint256) {
        require(msg.sender == investmentManager, "Only the investment manager can deposit into this strategy");
        require(token == depositToken, "Can only deposit this strategy's token");
        //deposit and the "shares" are the new aTokens minted
        uint256 aTokenIncrease = aToken.balanceOf(address(this));
        token.transferFrom(depositer, address(this), amount);
        lendingPool.deposit(
            address(token),
            amount,
            address(this),
            0
        );
        aTokenIncrease = aToken.balanceOf(address(this)) - aTokenIncrease;
        return aTokenIncrease;
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
        uint256 amountWithdrawn = lendingPool.withdraw(
            address(token),
            amounts[0],
            depositer
        );
        return amountWithdrawn;
    }

    function explanation() external pure returns (string memory) {
        return "A simple investment strategy that allows a single asset to be deposited and loans it out on Aave";
    }

    function updateAToken(IERC20 _aToken) external {
        require(governer == msg.sender, "Only governer can change the aToken");
        aToken = _aToken;
    }

    function totalShares() public view returns(uint256) {
        return aToken.balanceOf(address(this));
    }
}
