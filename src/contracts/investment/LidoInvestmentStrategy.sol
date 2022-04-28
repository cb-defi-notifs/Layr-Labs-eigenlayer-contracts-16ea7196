// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


import "../interfaces/IInvestmentManager.sol";
import "ds-test/test.sol";



contract LidoInvestmentStrategy is 
    Initializable, 
    IInvestmentStrategy,
    DSTest
{

    IERC20 public steth;


    function initialize(IERC20 _steth) public initializer {
        steth = _steth;
    }

    fallback() external payable {
        // protection against accidental submissions by calling non-existent function
        require(msg.data.length == 0, "NON_EMPTY_DATA");
        IERC20 token = steth;
        uint256 amount = 45;
        emit log_named_uint("BRO WHAT", 2);
        uint256 shares = deposit(token, amount);
    }
    /**
    * @notice Send funds to the pool with optional _referral parameter
    * @dev This function is alternative way to submit funds. Supports optional referral address.
    * @return Amount of StETH shares generated
    */
    function deposit(IERC20 token, uint256 amount) public returns (uint256) {
        
        address sender = msg.sender;
        uint256 deposit = 5;
        require(deposit != 0, "ZERO_DEPOSIT");

        uint256 sharesAmount = deposit;
        return sharesAmount;
    }

    function withdraw(address depositor, IERC20 token, uint256 amount) external{
        depositor = address(0);
    }

    function explanation() external pure returns (string memory) {
        return "A simple investment strategy that allows staking in LIDO";
    }
    function underlyingEthValueOfShares(uint256 numShares) public view virtual returns(uint256){
        return numShares;    
    }
    function underlyingEthValueOfSharesView(uint256 numShares) public view virtual returns(uint256){
        return numShares;
    }



}
