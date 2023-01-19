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


    uint256 GWEI_TO_WEI = 1e9;

    function setUp() override virtual public{
        EigenLayerDeployer.setUp();

        slasherMock = new SlasherMock();
        delegationMock = EigenLayerDelegation(address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), "")));
        investmentManagerMock = new InvestmentManagerMock(delegationMock, eigenPodManager, slasherMock);

        delegationMockImplementation = new EigenLayerDelegation(investmentManagerMock, slasherMock);

        eigenLayerProxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(delegationMock))), address(delegationMockImplementation));

        delegationMock.initialize(eigenLayerPauserReg, address(this));

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


}