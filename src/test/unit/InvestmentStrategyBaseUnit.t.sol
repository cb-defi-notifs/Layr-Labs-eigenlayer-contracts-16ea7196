// //SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "../mocks/ERC20Mock.sol";
import "../mocks/InvestmentManagerMock.sol";






import "../../contracts/strategies/InvestmentStrategyBase.sol";



import "../EigenLayerTestHelper.t.sol";
import "../mocks/DelegationMock.sol";
import "../mocks/SlasherMock.sol";


contract InvestmentStrategyBaseUnitTests {

    InvestmentStrategyBase public investmentStrategy;
    InvestmentManager public investmentManagerMock;
    IERC20 public tokenMock;

    uint256 GWEI_TO_WEI = 1e9;

    function setUp() virtual public {
        // investmentStrategy = 
    }
}