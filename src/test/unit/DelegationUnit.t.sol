// //SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";

import "../mocks/InvestmentManagerMock.sol";

import "../mocks/SlasherMock.sol";
import "../EigenLayerTestHelper.t.sol";
import "../mocks/ERC20Mock.sol";
import "../mocks/DelegationTermsMock.sol";
import "../Delegation.t.sol";


contract DelegationUnitTests is EigenLayerTestHelper {

    InvestmentManagerMock investmentManagerMock;
    SlasherMock slasherMock;
    EigenLayerDelegation delegationMock;
    DelegationTermsMock delegationTermsMock;
    EigenLayerDelegation delegationMockImplementation;
    InvestmentStrategyBase investmentStrategyImplementation;
    InvestmentStrategyBase investmentStrategyMock;


    uint256 GWEI_TO_WEI = 1e9;

    event OnDelegationReceivedCallFailure(IDelegationTerms indexed delegationTerms, bytes32 returnData);
    event OnDelegationWithdrawnCallFailure(IDelegationTerms indexed delegationTerms, bytes32 returnData);


    function setUp() override virtual public{
        EigenLayerDeployer.setUp();

        slasherMock = new SlasherMock();
        delegationTermsMock = new DelegationTermsMock();
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

    function testUndelegateFromNonInvestmentManagerAddress(address undelegator) public fuzzedAddress(undelegator){
        cheats.assume(undelegator != address(investmentManagerMock));
        cheats.expectRevert(bytes("onlyInvestmentManager"));
        cheats.startPrank(undelegator);
        delegationMock.undelegate(address(this));
    }

    function testUndelegateByOperatorFromThemselves(address operator) public fuzzedAddress(operator){
        cheats.startPrank(operator);
        delegationMock.registerAsOperator(IDelegationTerms(address(this)));
        cheats.stopPrank();
        cheats.expectRevert(bytes("EigenLayerDelegation.undelegate: operators cannot undelegate from themselves"));
        
        cheats.startPrank(address(investmentManagerMock));
        delegationMock.undelegate(operator);
        cheats.stopPrank();
    }

    function testIncreaseDelegatedSharesFromNonInvestmentManagerAddress(address operator, uint256 shares) public fuzzedAddress(operator){
        cheats.assume(operator != address(investmentManagerMock));
        cheats.expectRevert(bytes("onlyInvestmentManager"));
        cheats.startPrank(operator);
        delegationMock.increaseDelegatedShares(operator, investmentStrategyMock, shares);
    }

    function testDecreaseDelegatedSharesFromNonInvestmentManagerAddress(
        address operator,  
        IInvestmentStrategy[] memory strategies,  
        uint256[] memory shareAmounts
    ) public fuzzedAddress(operator){
        cheats.assume(operator != address(investmentManagerMock));
        cheats.expectRevert(bytes("onlyInvestmentManager"));
        cheats.startPrank(operator);
        delegationMock.decreaseDelegatedShares(operator, strategies, shareAmounts);
    }

    function testDelegateWhenOperatorIsFrozen(address operator, address staker) public fuzzedAddress(operator) fuzzedAddress(staker){
        
        cheats.startPrank(operator);
        delegationMock.registerAsOperator(IDelegationTerms(address(this)));
        cheats.stopPrank();

        slasherMock.setOperatorStatus(operator, true);
        cheats.expectRevert(bytes("EigenLayerDelegation._delegate: cannot delegate to a frozen operator"));
        cheats.startPrank(staker);
        delegationMock.delegateTo(operator);
        cheats.stopPrank();
    }

    function testDelegateWhenStakerHasExistingDelegation(address staker, address operator, address operator2) public{
        cheats.assume(operator != operator2);
        cheats.assume(staker != operator);
        cheats.assume(staker != operator2);

        cheats.startPrank(operator);
        delegationMock.registerAsOperator(IDelegationTerms(address(11)));
        cheats.stopPrank();

        cheats.startPrank(operator2);
        delegationMock.registerAsOperator(IDelegationTerms(address(10)));
        cheats.stopPrank();

        cheats.startPrank(staker);
        delegationMock.delegateTo(operator);
        cheats.stopPrank();

        cheats.startPrank(staker);
        cheats.expectRevert(bytes("EigenLayerDelegation._delegate: staker has existing delegation"));
        delegationMock.delegateTo(operator2);
        cheats.stopPrank();
    }

    function testDelegationToUnregisteredOperator(address operator) public{
        cheats.expectRevert(bytes("EigenLayerDelegation._delegate: operator has not yet registered as a delegate"));
        delegationMock.delegateTo(operator);
    }

    function testDelegationWhenPausedNewDelegationIsSet(address operator, address staker) public fuzzedAddress(operator) fuzzedAddress(staker){
        cheats.startPrank(pauser);
        delegationMock.pause(1);
        cheats.stopPrank();

        cheats.startPrank(staker);
        cheats.expectRevert(bytes("Pausable: index is paused"));
        delegationMock.delegateTo(operator);
        cheats.stopPrank();
    }

    function testRevertingDelegationReceivedHook(address operator, address staker) public fuzzedAddress(operator) fuzzedAddress(staker){
        delegationTermsMock.setShouldRevert(true);
        cheats.startPrank(operator);
        delegationMock.registerAsOperator(delegationTermsMock);
        cheats.stopPrank();

        cheats.startPrank(staker);
        cheats.expectEmit(true, false, false, false);
        emit OnDelegationReceivedCallFailure(delegationTermsMock, 0x0000000000000000000000000000000000000000000000000000000000000000);
        delegationMock.delegateTo(operator);
        cheats.stopPrank();
    }

    function testRevertingDelegationWithdrawnHook(
        address operator, 
        address staker
    ) public fuzzedAddress(operator) fuzzedAddress(staker){
        cheats.assume(operator != staker);
        delegationTermsMock.setShouldRevert(true);

        cheats.startPrank(operator);
        delegationMock.registerAsOperator(delegationTermsMock);
        cheats.stopPrank();

        cheats.startPrank(staker);
        delegationMock.delegateTo(operator);
        cheats.stopPrank();

        (IInvestmentStrategy[] memory updatedStrategies, uint256[] memory updatedShares) =
            investmentManager.getDeposits(staker);

        cheats.startPrank(address(investmentManagerMock));
        cheats.expectEmit(true, false, false, false);
        emit OnDelegationWithdrawnCallFailure(delegationTermsMock, 0x0000000000000000000000000000000000000000000000000000000000000000);
        delegationMock.decreaseDelegatedShares(staker, updatedStrategies, updatedShares);
        cheats.stopPrank();
    }

    function testDelegationReceivedHookWithTooMuchReturnData(address operator, address staker) public fuzzedAddress(operator) fuzzedAddress(staker){
        cheats.assume(operator != staker);
        cheats.startPrank(operator);
        delegationMock.registerAsOperator(delegationTermsMock);
        cheats.stopPrank();

        cheats.startPrank(staker);
        delegationMock.delegateTo(operator);
        cheats.stopPrank();
    }

    function testDelegationWithdrawnHookWithTooMuchReturnData(
        address operator, 
        address staker
    ) public fuzzedAddress(operator) fuzzedAddress(staker){
        cheats.assume(operator != staker);

        cheats.startPrank(operator);
        delegationMock.registerAsOperator(delegationTermsMock);
        cheats.stopPrank();

        cheats.startPrank(staker);
        delegationMock.delegateTo(operator);
        cheats.stopPrank();

        (IInvestmentStrategy[] memory updatedStrategies, uint256[] memory updatedShares) =
            investmentManager.getDeposits(staker);

        cheats.startPrank(address(investmentManagerMock));
        delegationMock.decreaseDelegatedShares(staker, updatedStrategies, updatedShares);
        cheats.stopPrank();
    }

}