// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IInvestmentManager.sol";
import "./aave/ILendingPool.sol";
import "./storage/AaveInvestmentStrategyStorage.sol";
import "../utils/Initializable.sol";
import "../utils/Governed.sol";

abstract contract AaveInvestmentStrategy is Initializable, Governed, AaveInvestmentStrategyStorage, IInvestmentStrategy {
    modifier onlyInvestmentManager() {
        require(msg.sender == investmentManager, "onlyInvestmentManager");
        _;
    }

    function initialize (ILendingPool _lendingPool, IERC20 _underlyingToken, IERC20 _aToken, address _investmentManager
    ) initializer public {
        _transferGovernor(msg.sender);
        lendingPool = _lendingPool;
        underlyingToken = _underlyingToken;
        aToken = _aToken;
        investmentManager = _investmentManager;
        _underlyingToken.approve(address(_lendingPool), type(uint256).max);
    }

    function deposit(
        IERC20 token,
        uint256 amount
    ) external onlyInvestmentManager returns (uint256 newShares) {
        uint256 aTokenIncrease;
        uint256 aTokensBefore;
        if (token == underlyingToken) {
            //deposit and the "shares" are in proportion to the new aTokens minted
            aTokensBefore = aToken.balanceOf(address(this));
            //tokens have already been transferred to this contract
            //underlyingToken.transferFrom(depositor, address(this), amounts[0]);
            lendingPool.deposit(
                address(underlyingToken),
                amount,
                address(this),
                0
            );
            aTokenIncrease = aToken.balanceOf(address(this)) - aTokensBefore;
        } else if (token == aToken) {
            aTokenIncrease = amount;
            aTokensBefore = aToken.balanceOf(address(this)) - amount;
        } else {
            revert("can only deposit underlyingToken or aToken");
        }
        if (totalShares == 0) {
            newShares = aTokenIncrease;
        } else {
            newShares = (aTokenIncrease * totalShares) / aTokensBefore;
        }
        totalShares += newShares;
    }

    function withdraw(
        address depositor,
        IERC20 token,
        uint256 shareAmount
    ) external onlyInvestmentManager returns(uint256 amountWithdrawn) {
        uint256 toWithdraw = sharesToUnderlying(shareAmount);
        if (token == underlyingToken) {
            //withdraw from lendingPool
            amountWithdrawn = lendingPool.withdraw(
                address(underlyingToken),
                toWithdraw,
                depositor
            );
            underlyingToken.transfer(depositor, amountWithdrawn);
        } else if (token == aToken) {
            aToken.transfer(depositor, toWithdraw);
            amountWithdrawn = toWithdraw;
        } else {
            revert("can only withdraw as underlyingToken or aToken");
        }
        totalShares -= shareAmount;
        return amountWithdrawn;
    }

    function explanation() external pure returns (string memory) {
        return "A simple investment strategy that allows a single asset to be deposited and loans it out on Aave";
    }

    function updateAToken(IERC20 _aToken) external onlyGovernor {
        aToken = _aToken;
    }

    // implementation for these functions in particular may vary for different underlying tokens
    // thus, they are left as unimplimented in this general contract
    function underlyingEthValueOfShares(uint256 numShares) public view virtual returns(uint256);
    function underlyingEthValueOfSharesView(uint256 numShares) public view virtual returns(uint256);

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
    function userUnderlying(address user) public view returns(uint256) {
        return sharesToUnderlying(shares(user));
    }
    function userUnderlyingView(address user) public view returns(uint256) {
        return sharesToUnderlyingView(shares(user));
    }
    function shares(address user) public view returns(uint256) {
        return IInvestmentManager(investmentManager).investorStratShares(user, IInvestmentStrategy(address(this)));
    }
}
