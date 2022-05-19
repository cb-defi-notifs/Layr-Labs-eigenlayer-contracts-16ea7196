// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IInvestmentManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../utils/Initializable.sol";

contract InvestmentStrategyBase is
    Initializable,
    IInvestmentStrategy
{
    IERC20 public immutable underlyingToken;
    address public immutable investmentManager;
    uint256 public totalShares;

    modifier onlyInvestmentManager() {
        require(msg.sender == investmentManager, "onlyInvestmentManager");
        _;
    }
    
    constructor(address _investmentManager, IERC20 _underlyingToken) {
        investmentManager = _investmentManager;
        underlyingToken = _underlyingToken;
    }

    function deposit(IERC20 token, uint256 amount)
        external view
        onlyInvestmentManager
        returns (uint256 newShares)
    {
        require(token == underlyingToken, "Can only deposit underlyingToken");
        return amount;
    }

    function withdraw(
        address depositor,
        IERC20 token,
        uint256 shareAmount
    ) external onlyInvestmentManager {
        require(token == underlyingToken, "Can only withdraw the strategy token");
        underlyingToken.transfer(depositor, shareAmount);
    }

    function explanation() external pure returns (string memory) {
        return "Base InvestmentStrategy implementation to inherit from";
    }

    // implementation for these functions in particular may vary for different underlying tokens & strategies
    function sharesToUnderlyingView(uint256 amountShares)
        public
        view
        returns (uint256)
    {
        return (_underlyingTokenBalance() * amountShares) / totalShares;
    }

    /**
     * @notice get a conversion of aToken from the input shares
     */
    /**
     * @param amountShares is the number of shares whose conversion is to be checked
     */
    function sharesToUnderlying(uint256 amountShares)
        public
        view
        returns (uint256)
    {
        return (_underlyingTokenBalance() * amountShares) / totalShares;
    }

    function underlyingToSharesView(uint256 amountUnderlying)
        public
        view
        returns (uint256)
    {
        return (amountUnderlying * totalShares) / _underlyingTokenBalance();
    }

    /**
     * @notice get a conversion of inout aToken to the shares at current price
     */
    /**
     * @param amountUnderlying is the amount of aToken for which number of shares is to be checked
     */
    function underlyingToShares(uint256 amountUnderlying)
        public
        view
        returns (uint256)
    {
        return (amountUnderlying * totalShares) / _underlyingTokenBalance();
    }

    function userUnderlying(address user) public view returns (uint256) {
        return sharesToUnderlying(shares(user));
    }

    function userUnderlyingView(address user) public view returns (uint256) {
        return sharesToUnderlyingView(shares(user));
    }

    function shares(address user) public view returns (uint256) {
        return
            IInvestmentManager(investmentManager).investorStratShares(
                user,
                IInvestmentStrategy(address(this))
            );
    }

    function _underlyingTokenBalance() internal view returns(uint256) {
        return underlyingToken.balanceOf(address(this));
    }
}
