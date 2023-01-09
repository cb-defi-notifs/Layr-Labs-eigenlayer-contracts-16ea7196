// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../src/contracts/interfaces/IInvestmentManager.sol";
import "../../src/contracts/interfaces/IInvestmentStrategy.sol";
import "../../src/contracts/interfaces/IEigenLayrDelegation.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/Test.sol";

contract Staker is Ownable, Test {
    //TODO: change before deploy
    //IInvestmentManager constant investmentManager = IInvestmentManager(0x0000000000000000000000000000000000000000);
    //IEigenLayrDelegation constant delegation = IEigenLayrDelegation(0x0000000000000000000000000000000000000000);

    constructor(
        IInvestmentStrategy strategy, 
        IInvestmentManager investmentManager,
        IEigenLayrDelegation delegation,
        IERC20 token, 
        uint256 amount, 
        address operator,
        address whiteLister
    ) Ownable() {
        token.approve(address(investmentManager), type(uint256).max);
        emit log_named_address("address(staker)", address(this));
        emit log_named_uint("address(staker) balance ", token.balanceOf(address(this)));

        investmentManager.depositIntoStrategy(strategy, token, amount);
        delegation.delegateTo(operator);
    }

    // add proxy call for further things we may we want to do
    fallback() external onlyOwner {
        (address to, bytes memory data) = abi.decode(msg.data, (address, bytes));
        assembly {
            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := call(gas(), to, callvalue(), data, mload(data), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}