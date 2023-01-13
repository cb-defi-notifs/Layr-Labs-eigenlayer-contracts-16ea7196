// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../src/contracts/interfaces/IInvestmentManager.sol";
import "../../src/contracts/interfaces/IInvestmentStrategy.sol";
import "../../src/contracts/interfaces/IEigenLayerDelegation.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/Test.sol";

contract Staker is Ownable, Test {
    
    constructor(
        IInvestmentStrategy strategy, 
        IInvestmentManager investmentManager,
        IEigenLayerDelegation delegation,
        IERC20 token, 
        uint256 amount, 
        address operator
    ) Ownable() {
        token.approve(address(investmentManager), type(uint256).max);
        investmentManager.depositIntoStrategy(strategy, token, amount);
        delegation.delegateTo(operator);
    }
    
    function callAddress(address implementation, bytes memory data) external onlyOwner returns(bytes memory) {
        uint256 length = data.length;
        bytes memory returndata;  
        assembly{
            let result := call(
                gas(),
                implementation,
                callvalue(),
                add(data, 32),
                length,
                0,
                0
            )
            mstore(returndata, returndatasize())
            returndatacopy(add(returndata, 32), 0, returndatasize())
        }
        emit log_bytes(returndata);

        return returndata;

    }

}