// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IInvestmentManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../utils/Initializable.sol";
import "../utils/Governed.sol";


contract HollowInvestmentStrategy is
    Initializable,
    Governed,
    IInvestmentStrategy
{
    address public investmentManager;
    uint256 public totalShares;
    modifier onlyInvestmentManager() {
        require(msg.sender == investmentManager, "onlyInvestmentManager");
        _;
    }
    
    constructor() {
    }

    function initialize(address _investmentManager)
        public
        initializer
    {
        _transferGovernor(msg.sender);
        investmentManager = _investmentManager;
    }

    function deposit(IERC20 token, uint256 amount)
        external
        onlyInvestmentManager
        returns (uint256 newShares)
    {
        require(token == IERC20(address(0)), "Must pass in 0 token to make sure not actually sending tokens");
        totalShares += amount;
        return amount;
    }

    function withdraw(
        address,
        IERC20,
        uint256 shareAmount
    ) external onlyInvestmentManager {
        totalShares -= shareAmount;
    }

    function explanation() external pure returns (string memory) {
        return "A simple investment strategy that just stashes WETH";
    }

    // implementation for these functions in particular may vary for different underlying tokens
    // thus, they are left as unimplimented in this general contract
    function underlyingEthValueOfShares(uint256 numShares)
        public
        pure
        virtual
        returns (uint256)
    {
        return numShares;
    }

    function underlyingEthValueOfSharesView(uint256 numShares)
        public
        pure
        virtual
        returns (uint256)
    {
        return numShares;
    }

    function sharesToUnderlyingView(uint256 amountShares)
        public
        pure
        returns (uint256)
    {
        return amountShares;
    }

    /**
     * @notice get a conversion of aToken from the input shares
     */
    /**
     * @param amountShares is the number of shares whose conversion is to be checked
     */
    function sharesToUnderlying(uint256 amountShares)
        public
        pure
        returns (uint256)
    {
        return amountShares;
    }

    function underlyingToSharesView(uint256 amountUnderlying)
        public
        pure
        returns (uint256)
    {
        return amountUnderlying;
    }

    /**
     * @notice get a conversion of inout aToken to the shares at current price
     */
    /**
     * @param amountUnderlying is the amount of aToken for which number of shares is to be checked
     */
    function underlyingToShares(uint256 amountUnderlying)
        public
        pure
        returns (uint256)
    {
        return amountUnderlying;
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
}
