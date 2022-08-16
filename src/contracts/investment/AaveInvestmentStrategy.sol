// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./aave/ILendingPool.sol";
import "./AaveInvestmentStrategyStorage.sol";
import "./InvestmentStrategyBase.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

abstract contract AaveInvestmentStrategy is Initializable, AaveInvestmentStrategyStorage, InvestmentStrategyBase {

    constructor(IInvestmentManager _investmentManager) 
        InvestmentStrategyBase(_investmentManager)
    {}

    function initialize(IERC20 _underlyingToken, ILendingPool _lendingPool, IERC20 _aToken
    ) initializer public {
        super.initialize(_underlyingToken);
        lendingPool = _lendingPool;
        aToken = _aToken;
        underlyingToken.approve(address(_lendingPool), type(uint256).max);
    }


    /**
     * @notice Used for depositing assets into Aave
     */
    /**
     * @return newShares is the number of shares issued at the current price for each share
     *         in terms of aToken. 
     */
    function deposit(
        IERC20 token,
        uint256 amount
    ) external override onlyInvestmentManager returns (uint256 newShares) {
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

            // increment in the aToken balance of this contract due to the new investment
            aTokenIncrease = aToken.balanceOf(address(this)) - aTokensBefore;
        } else if (token == aToken) {
            aTokenIncrease = amount;

            // total aToken with this contract before the new investment,
            // this includes interest rates accrued on existing investment
            aTokensBefore = aToken.balanceOf(address(this)) - amount;
        } else {
            revert("AaveInvestmentStrategy.deposit: can only deposit underlyingToken or aToken");
        }
        if (totalShares == 0) {
            // no existing investment into this investment strategy
            newShares = aTokenIncrease;
        } else {
            /**
             * @dev Evaluating the number of new shares that would be issued for the increase
             *      in aToken at the current price of each share in terms of aToken. This 
             *      price is given by aTokensBefore / totalShares.  
             */
            newShares = (aTokenIncrease * totalShares) / aTokensBefore;
        }

        // incrementing the total number of shares
        totalShares += newShares;
    }


    /**
     * @notice Used for withdrawing assets from Aave in the specified token
     */
    /**
     * @param depositor is the withdrawer's address
     * @param token is the token in which deposter intends to get back its assets
     * @param shareAmount is the amount of share that the depositor wants to exchange for 
     *        withdrawing its assets
     */
    function withdraw(
        address depositor,
        IERC20 token,
        uint256 shareAmount
    ) external override onlyInvestmentManager {
        uint256 toWithdraw = sharesToUnderlying(shareAmount);

        if (token == underlyingToken) {
            //withdraw from lendingPool
            uint256 amountWithdrawn = lendingPool.withdraw(
                address(underlyingToken),
                toWithdraw,
                depositor
            );

            // transfer the underlyingToken to the depositor
            underlyingToken.transfer(depositor, amountWithdrawn);

        } else if (token == aToken) {
            aToken.transfer(depositor, toWithdraw);
        } else {
            revert("can only withdraw as underlyingToken or aToken");
        }

        // update the total shares for this investment strategy
        totalShares -= shareAmount;
    }

    
    function explanation() external pure override returns (string memory) {
        return "A simple investment strategy that allows a single asset to be deposited and loans it out on Aave";
    }

    function _tokenBalance() internal view override returns(uint256) {
        return aToken.balanceOf(address(this));
    }
}
