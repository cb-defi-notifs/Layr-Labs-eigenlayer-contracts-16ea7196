// //SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";

import "../mocks/InvestmentManagerMock.sol";

import "../mocks/SlasherMock.sol";
import "../EigenLayerTestHelper.t.sol";
import "../mocks/ERC20Mock.sol";


contract InvestmentManagerUnitTests is EigenLayerTestHelper {

    InvestmentManagerMock investmentManagerMock;
    SlasherMock slasherMock;
    EigenLayerDelegation delegationMock;
    EigenLayerDelegation delegationMockImplementation;
    InvestmentStrategyBase investmentStrategyImplementation;
    InvestmentStrategyBase investmentStrategyMock;


    uint256 GWEI_TO_WEI = 1e9;

    function setUp() override virtual public{
        EigenLayerDeployer.setUp();

        slasherMock = new SlasherMock();
        delegationMock = EigenLayerDelegation(address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), "")));
        investmentManagerMock = new InvestmentManagerMock(delegationMock, eigenPodManager, slasherMock);

        delegationMockImplementation = new EigenLayerDelegation(investmentManagerMock, slasherMock);

        eigenLayerProxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(delegationMock))), address(delegationMockImplementation));

        delegationMock.initialize(eigenLayerPauserReg, address(this));

        investmentStrategyImplementation = new InvestmentStrategyBase(investmentManager);

        investmentStrategyMock = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(investmentStrategyImplementation),
                    address(eigenLayerProxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, weth, eigenLayerPauserReg)
                )
            )
        );

    }

    function testReinitializeDelegation() public{
        cheats.expectRevert(bytes("Initializable: contract is already initialized"));
        delegationMock.initialize(eigenLayerPauserReg, address(this));
    }

    function testBadECDSASignatureExpiry(address staker, address operator, uint256 expiry, bytes memory signature) public{
        cheats.assume(expiry < block.timestamp);
        cheats.expectRevert(bytes("EigenLayerDelegation.delegateToBySignature: delegation signature expired"));
        delegationMock.delegateToBySignature(staker, operator, expiry, signature);
    }

    function testUndelegateFromNonInvestmentManagerAddress(address undelegator) public{
        cheats.assume(undelegator != address(investmentManagerMock));
        cheats.expectRevert(bytes("onlyInvestmentManager"));
        cheats.startPrank(undelegator);
        delegationMock.undelegate(address(this));
    }

    function testUndelegateByOperatorFromThemselves(address operator) public{
        cheats.startPrank(operator);
        delegationMock.registerAsOperator(IDelegationTerms(address(this)));
        cheats.stopPrank();
        cheats.expectRevert(bytes("EigenLayerDelegation.undelegate: operators cannot undelegate from themselves"));
        
        cheats.startPrank(address(investmentManagerMock));
        delegationMock.undelegate(operator);
        cheats.stopPrank();
    }

    function testIncreaseDelegatedSharesFromNonInvestmentManagerAddress(address operator, uint256 shares) public{
        cheats.assume(operator != address(investmentManagerMock));
        cheats.expectRevert(bytes("onlyInvestmentManager"));
        cheats.startPrank(operator);
        delegationMock.increaseDelegatedShares(operator, investmentStrategyMock, shares);
    }

    function testDecreaseDelegatedSharesFromNonInvestmentManagerAddress(address operator,  IInvestmentStrategy[] memory strategies,  uint256[] memory shareAmounts) public{
        cheats.assume(operator != address(investmentManagerMock));
        cheats.expectRevert(bytes("onlyInvestmentManager"));
        cheats.startPrank(operator);
        delegationMock.decreaseDelegatedShares(operator, strategies, shareAmounts);
    }

    function testDelegateWhenOperatorIsFrozen(address operator) public{
        cheats.startPrank(operator);
        delegationMock.registerAsOperator(IDelegationTerms(address(this)));
        cheats.stopPrank();

        slasherMock.setOperatorStatus(operator, true);
        cheats.expectRevert(bytes("EigenLayerDelegation._delegate: cannot delegate to a frozen operator"));
        delegationMock.delegateTo(operator);
    }

    function testDelegateWhenStakerHasExistingDelegation(address staker, address operator, address operator2) public{
        cheats.startPrank(operator);
        delegationMock.registerAsOperator(IDelegationTerms(address(this)));
        cheats.stopPrank();

        cheats.startPrank(operator2);
        delegationMock.registerAsOperator(IDelegationTerms(address(this)));
        cheats.stopPrank();

        cheats.startPrank(staker);
        delegationMock.delegateTo(operator);
        cheats.stopPrank();

        delegationMock.delegateTo(operator);

        cheats.expectRevert(bytes("EigenLayerDelegation._delegate: staker has existing delegation"));
        delegationMock.delegateTo(operator2);
    }

}