// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IInvestmentManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

contract InvestmentStrategyBase is
    Initializable,
    IInvestmentStrategy
{
    address public investmentManager;
    IERC20 public underlyingToken;
    uint256 public totalShares;

    modifier onlyInvestmentManager() {
        require(msg.sender == address(investmentManager), "InvestmentStrategyBase.onlyInvestmentManager");
        _;
    }

    constructor() {
        // TODO: uncomment for production use!
        //_disableInitializers();
    }

    function initialize(address _investmentManager, IERC20 _underlyingToken) initializer public {
        investmentManager = _investmentManager;
        underlyingToken = _underlyingToken;
    }

    function deposit(IERC20 token, uint256 amount)
        external virtual override
        onlyInvestmentManager
        returns (uint256 newShares)
    {
        require(token == underlyingToken, "InvestmentStrategyBase.deposit: Can only deposit underlyingToken");
        newShares = amount;
        totalShares += newShares;
        return newShares;
    }

    function withdraw(
        address depositor,
        IERC20 token,
        uint256 shareAmount
    ) external virtual override onlyInvestmentManager {
        require(token == underlyingToken, "InvestmentStrategyBase.withdraw: Can only withdraw the strategy token");
        require(shareAmount <= totalShares, "InvestmentStrategyBase.withdraw: withdrawal amount must be greater than total shares");
        totalShares -= shareAmount;
        underlyingToken.transfer(depositor, shareAmount);
    }

    function explanation() external pure virtual override returns (string memory) {
        return "Base InvestmentStrategy implementation to inherit from";
    }

    // implementation for these functions in particular may vary for different underlying tokens & strategies
    function sharesToUnderlyingView(uint256 amountShares)
        public
        view virtual override
        returns (uint256)
    {
        if (totalShares == 0) {
            return amountShares;
        } else {
            return (_tokenBalance() * amountShares) / totalShares;            
        }
    }

    /**
     * @notice get a conversion of aToken from the input shares
     */
    /**
     * @param amountShares is the number of shares whose conversion is to be checked
     */
    function sharesToUnderlying(uint256 amountShares)
        public
        view virtual override
        returns (uint256)
    {
        return sharesToUnderlyingView(amountShares);
    }

    function underlyingToSharesView(uint256 amountUnderlying)
        public
        view virtual
        returns (uint256)
    {
        uint256 tokenBalance = _tokenBalance();
        if (tokenBalance == 0 || totalShares == 0) {
            return amountUnderlying;
        } else {
            return (amountUnderlying * totalShares) / tokenBalance;            
        }
    }

    /**
     * @notice get a conversion of inout aToken to the shares at current price
     */
    /**
     * @param amountUnderlying is the amount of aToken for which number of shares is to be checked
     */
    function underlyingToShares(uint256 amountUnderlying)
        public
        view virtual
        returns (uint256)
    {
        return underlyingToSharesView(amountUnderlying);
    }

    function userUnderlying(address user) public view virtual returns (uint256) {
        return sharesToUnderlying(shares(user));
    }

    function userUnderlyingView(address user) public view virtual returns (uint256) {
        return sharesToUnderlyingView(shares(user));
    }

    function shares(address user) public view virtual returns (uint256) {
        return
            IInvestmentManager(investmentManager).investorStratShares(
                user,
                IInvestmentStrategy(address(this))
            );
    }

    function _tokenBalance() internal view virtual returns(uint256) {
        return underlyingToken.balanceOf(address(this));
    }
}
