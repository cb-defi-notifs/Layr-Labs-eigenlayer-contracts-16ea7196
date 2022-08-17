// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IInvestmentManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

contract InvestmentStrategyBase is
    Initializable,
    IInvestmentStrategy
{
    IInvestmentManager public immutable investmentManager;
    IERC20 public underlyingToken;
    uint256 public totalShares;

    modifier onlyInvestmentManager() {
        require(msg.sender == address(investmentManager), "InvestmentStrategyBase.onlyInvestmentManager");
        _;
    }

    constructor(IInvestmentManager _investmentManager) {
        investmentManager = _investmentManager;
        // TODO: uncomment for production use!
        //_disableInitializers();
    }

    function initialize(IERC20 _underlyingToken) initializer public {
        underlyingToken = _underlyingToken;
    }

    /**
     * @notice Used to deposit tokens into this InvestmentStrategy
     * @param token is the ERC20 token being deposited
     * @param amount is the amount of token being deposited
     * @dev This function is only callable by the investmentManager contract. It is invoked inside of the investmentManager's
     *       `depositIntoStrategy` function, and individual share balances are recorded in the investmentManager as well
     * @return newShares is the number of new shares issued at the current exchange ratio.
     *      For this simple strategy, the exchange ratio is fixed at (1 underlying token) / (1 share).
     */
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

    /**
     * @notice Used to withdraw tokens from this InvestmentStrategy, to the `depositor`'s address
     * @param token is the ERC20 token being transferred out
     * @param shareAmount is the amount of shares being withdrawn
     * @dev This function is only callable by the investmentManager contract. It is invoked inside of the investmentManager's
     *      other functions, and individual share balances are recorded in the investmentManager as well
     */
    function withdraw(
        address depositor,
        IERC20 token,
        uint256 shareAmount
    ) external virtual override onlyInvestmentManager {
        require(token == underlyingToken, "InvestmentStrategyBase.withdraw: Can only withdraw the strategy token");
        totalShares -= shareAmount;
        underlyingToken.transfer(depositor, shareAmount);
    }

    function explanation() external pure virtual override returns (string memory) {
        return "Base InvestmentStrategy implementation to inherit from";
    }

    /**
     * @notice Used to convert a number of shares to the equivalent amount of underlying tokens for this strategy.
     *          For this simple strategy in particular, the exchange rate is fixed at (1 underlying token) / (1 share).
     * @notice In contrast to `sharesToUnderlying`, this function guarantees no state modifications
     * @param amountShares is the amount of shares to calculate its conversion into the underlying token
     * @dev Implementation for these functions in particular may vary signifcantly for different strategies
     */
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
     * @notice Used to convert a number of shares to the equivalent amount of underlying tokens for this strategy.
     *          For this simple strategy in particular, the exchange rate is fixed at (1 underlying token) / (1 share).
     * @notice In contrast to `sharesToUnderlyingView`, this function **may** make state modifications
     * @param amountShares is the amount of shares to calculate its conversion into the underlying token
     * @dev Implementation for these functions in particular may vary signifcantly for different strategies
     */
    function sharesToUnderlying(uint256 amountShares)
        public
        view virtual override
        returns (uint256)
    {
        return sharesToUnderlyingView(amountShares);
    }

    /**
     * @notice Used to convert an amount of underlying tokens to the equivalent amount of shares in this strategy.
     *          For this simple strategy in particular, the exchange rate is fixed at (1 underlying token) / (1 share).
     * @notice In contrast to `underlyingToShares`, this function guarantees no state modifications
     * @param amountUnderlying is the amount of `underlyingToken` to calculate its conversion into strategy shares
     * @dev Implementation for these functions in particular may vary signifcantly for different strategies
     */
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
     * @notice Used to convert an amount of underlying tokens to the equivalent amount of shares in this strategy.
     *          For this simple strategy in particular, the exchange rate is fixed at (1 underlying token) / (1 share).
     * @notice In contrast to `underlyingToSharesView`, this function **may** make state modifications
     * @param amountUnderlying is the amount of `underlyingToken` to calculate its conversion into strategy shares
     * @dev Implementation for these functions in particular may vary signifcantly for different strategies
     */
    function underlyingToShares(uint256 amountUnderlying)
        public
        view virtual
        returns (uint256)
    {
        return underlyingToSharesView(amountUnderlying);
    }

    /**
     * @notice convenience function for fetching the current underlying value of all of the `user`'s shares in
     *         this strategy. In contrast to `userUnderlying`, this function guarantees no state modifications
     */
    function userUnderlyingView(address user) public view virtual returns (uint256) {
        return sharesToUnderlyingView(shares(user));
    }

    /**
     * @notice convenience function for fetching the current underlying value of all of the `user`'s shares in
     *         this strategy. In contrast to `userUnderlyingView`, this function **may** make state modifications
     */
    function userUnderlying(address user) public view virtual returns (uint256) {
        return sharesToUnderlying(shares(user));
    }

    /**
     * @notice convenience function for fetching the current total shares of `user` in this strategy, by
     *          querying the `investmentManager` contract
     */
    function shares(address user) public view virtual returns (uint256) {
        return
            IInvestmentManager(investmentManager).investorStratShares(
                user,
                IInvestmentStrategy(address(this))
            );
    }

    // internal function used to fetch this contract's current balance of `underlyingToken`
    function _tokenBalance() internal view virtual returns(uint256) {
        return underlyingToken.balanceOf(address(this));
    }
}
