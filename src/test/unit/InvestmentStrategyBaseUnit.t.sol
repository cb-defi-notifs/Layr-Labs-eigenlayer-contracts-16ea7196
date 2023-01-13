// //SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

import "../mocks/ERC20Mock.sol";
import "../mocks/InvestmentManagerMock.sol";






import "../../contracts/strategies/InvestmentStrategyBase.sol";



import "../EigenLayerTestHelper.t.sol";
import "../mocks/DelegationMock.sol";
import "../mocks/SlasherMock.sol";


contract InvestmentStrategyBaseUnitTests {

    IInvestmentManager public investmentManagerMock;
    IERC20 public tokenMock;
    InvestmentStrategyBase public investmentStrategy;

    uint256 GWEI_TO_WEI = 1e9;

    function setUp() virtual public {
        investmentManagerMock = new InvestmentManagerMock(
            IEigenLayerDelegation(address(this)),
            IEigenPodManager(address(this)),
            ISlasher(address(this))
        );

        

        // investmentStrategy = 
    }
}