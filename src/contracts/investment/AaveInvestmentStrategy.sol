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

            // increment in the aToken balance of this contract due to the new investment
            aTokenIncrease = aToken.balanceOf(address(this)) - aTokensBefore;
        } else if (token == aToken) {
            aTokenIncrease = amount;

            // total aToken with this contract before the new investment,
            // this includes interest rates accrued on existing investment
            aTokensBefore = aToken.balanceOf(address(this)) - amount;
        } else {
            revert("can only deposit underlyingToken or aToken");
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
    ) external onlyInvestmentManager {
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

    /**
     * @notice get a conversion of aToken from the input shares
     */
    /**
     * @param amountShares is the number of shares whose conversion is to be checked
     */ 
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

    /**
     * @notice get a conversion of inout aToken to the shares at current price
     */
    /**
     * @param amountUnderlying is the amount of aToken for which number of shares is to be checked
     */ 
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
