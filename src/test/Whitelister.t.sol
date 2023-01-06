// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../src/contracts/interfaces/IInvestmentManager.sol";
import "../../src/contracts/interfaces/IInvestmentStrategy.sol";
import "../../src/contracts/interfaces/IEigenLayrDelegation.sol";
import "../../src/contracts/strategies/InvestmentStrategyBase.sol";

import "../../script/whitelist/Staker.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

import "./EigenLayrDeployer.t.sol";

import "forge-std/Test.sol";

contract WhitelisterTests is EigenLayrDeployer, Test {

    ERC20PresetMinterPauser dummyToken;
    IInvestmentStrategy dummyStrat;

    function setUp() external{

        dummyToken = new ERC20PresetMinterPauser("dummy staked ETH", "dsETH");
        dummyStratImplementation = new InvestmentStrategyBase(investmentManager);
        dummyStrat = InvestmentStrategyBase(
            new TransparentUpgradeableProxy(
                    address(dummyStratImplementation),
                    address(eigenLayrProxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, dummyToken, eigenLayrPauserReg)
                )
        );
        
        
        

    }

    function testWhitelist() external {
        uint er = 4;
    }

}