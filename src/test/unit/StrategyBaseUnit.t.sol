// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../contracts/strategies/StrategyBase.sol";
import "../../contracts/permissions/PauserRegistry.sol";

import "../mocks/StrategyManagerMock.sol";
import "../mocks/ERC20_SetTransferReverting_Mock.sol";

import "forge-std/Test.sol";

contract StrategyBaseUnitTests is Test {

    Vm cheats = Vm(HEVM_ADDRESS);

    ProxyAdmin public proxyAdmin;
    PauserRegistry public pauserRegistry;
    IStrategyManager public strategyManager;
    IERC20 public underlyingToken;
    StrategyBase public strategyImplementation;
    StrategyBase public strategy;

    address public pauser = address(555);
    address public unpauser = address(999);

    uint256 initialSupply = 1e24;
    address initialOwner = address(this);

    uint256 public constant MIN_NONZERO_TOTAL_SHARES = 1e9;

    function setUp() virtual public {
        proxyAdmin = new ProxyAdmin();

        pauserRegistry = new PauserRegistry(pauser, unpauser);

        strategyManager = new StrategyManagerMock();

        underlyingToken = new ERC20PresetFixedSupply("Test Token", "TEST", initialSupply, initialOwner);

        strategyImplementation = new StrategyBase(strategyManager);

        strategy = StrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(strategyImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(StrategyBase.initialize.selector, underlyingToken, pauserRegistry)
                )
            )
        );
    }

    function testCannotReinitialize() public {
        cheats.expectRevert(bytes("Initializable: contract is already initialized"));
        strategy.initialize(underlyingToken, pauserRegistry);
    }

    function testInitialDepositCannotBeTooSmall(uint32 amountToDeposit) public {
        cheats.assume(amountToDeposit > 0 && amountToDeposit < MIN_NONZERO_TOTAL_SHARES);

        underlyingToken.transfer(address(strategy), amountToDeposit);

        cheats.expectRevert(bytes("StrategyBase.deposit: updated totalShares amount would be nonzero but below MIN_NONZERO_TOTAL_SHARES"));
        cheats.startPrank(address(strategyManager));
        strategy.deposit(underlyingToken, amountToDeposit);
        cheats.stopPrank();
    }

    function testCannotReceiveZeroShares() public {
        uint256 amountToDeposit = 0;

        cheats.startPrank(address(strategyManager));
        cheats.expectRevert(bytes("StrategyBase.deposit: newShares cannot be zero"));
        strategy.deposit(underlyingToken, amountToDeposit);
        cheats.stopPrank();
    }

    function testDepositWithZeroPriorBalanceAndZeroPriorShares(uint256 amountToDeposit) public {
        // sanity check / filter
        cheats.assume(amountToDeposit <= underlyingToken.balanceOf(address(this)));
        cheats.assume(amountToDeposit >= MIN_NONZERO_TOTAL_SHARES);

        uint256 totalSharesBefore = strategy.totalShares();

        underlyingToken.transfer(address(strategy), amountToDeposit);

        cheats.startPrank(address(strategyManager));
        uint256 newShares = strategy.deposit(underlyingToken, amountToDeposit);
        cheats.stopPrank();

        require(newShares == amountToDeposit, "newShares != amountToDeposit");
        uint256 totalSharesAfter = strategy.totalShares();
        require(totalSharesAfter - totalSharesBefore == newShares, "totalSharesAfter - totalSharesBefore != newShares");
    }

    function testDepositWithNonzeroPriorBalanceAndNonzeroPriorShares(uint256 priorTotalShares, uint256 amountToDeposit) public {
        cheats.assume(priorTotalShares >= MIN_NONZERO_TOTAL_SHARES && amountToDeposit > 0);

        testDepositWithZeroPriorBalanceAndZeroPriorShares(priorTotalShares);

        // sanity check / filter
        cheats.assume(amountToDeposit <= underlyingToken.balanceOf(address(this)));

        uint256 totalSharesBefore = strategy.totalShares();

        underlyingToken.transfer(address(strategy), amountToDeposit);

        cheats.startPrank(address(strategyManager));
        uint256 newShares = strategy.deposit(underlyingToken, amountToDeposit);
        cheats.stopPrank();

        require(newShares == amountToDeposit, "newShares != amountToDeposit");
        uint256 totalSharesAfter = strategy.totalShares();
        require(totalSharesAfter - totalSharesBefore == newShares, "totalSharesAfter - totalSharesBefore != newShares");
    }

    function testDepositFailsWhenDepositsPaused() public {
        // pause deposits
        cheats.startPrank(pauser);
        strategy.pause(1);
        cheats.stopPrank();

        uint256 amountToDeposit = 1e18;
        underlyingToken.transfer(address(strategy), amountToDeposit);

        cheats.expectRevert(bytes("Pausable: index is paused"));
        cheats.startPrank(address(strategyManager));
        strategy.deposit(underlyingToken, amountToDeposit);
        cheats.stopPrank();
    }

    function testDepositFailsWhenCallingFromNotStrategyManager(address caller) public {
        cheats.assume(caller != address(strategy.strategyManager()) && caller != address(proxyAdmin));

        uint256 amountToDeposit = 1e18;
        underlyingToken.transfer(address(strategy), amountToDeposit);

        cheats.expectRevert(bytes("StrategyBase.onlyStrategyManager"));
        cheats.startPrank(caller);
        strategy.deposit(underlyingToken, amountToDeposit);
        cheats.stopPrank();
    }

    function testDepositFailsWhenNotUsingUnderlyingToken(address notUnderlyingToken) public {
        cheats.assume(notUnderlyingToken != address(underlyingToken));

        uint256 amountToDeposit = 1e18;

        cheats.expectRevert(bytes("StrategyBase.deposit: Can only deposit underlyingToken"));
        cheats.startPrank(address(strategyManager));
        strategy.deposit(IERC20(notUnderlyingToken), amountToDeposit);
        cheats.stopPrank();
    }

    function testWithdrawWithPriorTotalSharesAndAmountSharesEqual(uint256 amountToDeposit) public {
        cheats.assume(amountToDeposit >= MIN_NONZERO_TOTAL_SHARES);
        testDepositWithZeroPriorBalanceAndZeroPriorShares(amountToDeposit);

        uint256 sharesToWithdraw = strategy.totalShares();
        uint256 strategyBalanceBefore = underlyingToken.balanceOf(address(strategy));

        uint256 tokenBalanceBefore = underlyingToken.balanceOf(address(this));
        cheats.startPrank(address(strategyManager));
        strategy.withdraw(address(this), underlyingToken, sharesToWithdraw);
        cheats.stopPrank();

        uint256 tokenBalanceAfter = underlyingToken.balanceOf(address(this));
        uint256 totalSharesAfter = strategy.totalShares();

        require(totalSharesAfter == 0, "shares did not decrease appropriately");
        require(tokenBalanceAfter - tokenBalanceBefore == strategyBalanceBefore, "tokenBalanceAfter - tokenBalanceBefore != strategyBalanceBefore");
    }

    function testWithdrawWithPriorTotalSharesAndAmountSharesNotEqual(uint96 amountToDeposit, uint96 sharesToWithdraw) public {
        cheats.assume(amountToDeposit >= MIN_NONZERO_TOTAL_SHARES);
        testDepositWithZeroPriorBalanceAndZeroPriorShares(amountToDeposit);

        uint256 totalSharesBefore = strategy.totalShares();
        uint256 strategyBalanceBefore = underlyingToken.balanceOf(address(strategy));

        // due to `MIN_NONZERO_TOTAL_SHARES` restrictions
        cheats.assume(totalSharesBefore >= sharesToWithdraw + MIN_NONZERO_TOTAL_SHARES || totalSharesBefore == sharesToWithdraw);

        uint256 tokenBalanceBefore = underlyingToken.balanceOf(address(this));

        cheats.startPrank(address(strategyManager));
        strategy.withdraw(address(this), underlyingToken, sharesToWithdraw);
        cheats.stopPrank();

        uint256 tokenBalanceAfter = underlyingToken.balanceOf(address(this));
        uint256 totalSharesAfter = strategy.totalShares();

        require(totalSharesBefore - totalSharesAfter == sharesToWithdraw, "shares did not decrease appropriately");
        require(tokenBalanceAfter - tokenBalanceBefore == (strategyBalanceBefore * sharesToWithdraw) / totalSharesBefore,
            "token balance did not increase appropriately");
    }

    function testWithdrawFailsWhenWouldResultInForbiddenTotalShareAmount(uint32 fuzzedInput) public {
        uint256 amountToDeposit = 1e18;
        testDepositWithZeroPriorBalanceAndZeroPriorShares(amountToDeposit);

        uint256 totalSharesBefore = strategy.totalShares();

        // filter so withdrawal will make 'totalShares' fall strictly between 0 and MIN_NONZERO_TOTAL_SHARES
        cheats.assume(fuzzedInput > 0 && fuzzedInput < MIN_NONZERO_TOTAL_SHARES);
        uint256 sharesToWithdraw = totalSharesBefore - fuzzedInput;

        cheats.startPrank(address(strategyManager));
        cheats.expectRevert(bytes("StrategyBase.withdraw: updated totalShares amount would be nonzero but below MIN_NONZERO_TOTAL_SHARES"));
        strategy.withdraw(address(this), underlyingToken, sharesToWithdraw);
        cheats.stopPrank();
    }

    function testWithdrawFailsWhenWithdrawalsPaused(uint256 amountToDeposit) public {
        cheats.assume(amountToDeposit >= MIN_NONZERO_TOTAL_SHARES);
        testDepositWithZeroPriorBalanceAndZeroPriorShares(amountToDeposit);

        // pause withdrawals
        cheats.startPrank(pauser);
        strategy.pause(2);
        cheats.stopPrank();

        uint256 amountToWithdraw = 1e18;

        cheats.expectRevert(bytes("Pausable: index is paused"));
        cheats.startPrank(address(strategyManager));
        strategy.withdraw(address(this), underlyingToken, amountToWithdraw);
        cheats.stopPrank();
    }

    function testWithdrawalFailsWhenCallingFromNotStrategyManager(address caller) public {
        cheats.assume(caller != address(strategy.strategyManager()) && caller != address(proxyAdmin));

        uint256 amountToDeposit = 1e18;
        testDepositWithZeroPriorBalanceAndZeroPriorShares(amountToDeposit);

        uint256 amountToWithdraw = 1e18;

        cheats.expectRevert(bytes("StrategyBase.onlyStrategyManager"));
        cheats.startPrank(caller);
        strategy.withdraw(address(this), underlyingToken, amountToWithdraw);
        cheats.stopPrank();
    }

    function testWithdrawalFailsWhenNotUsingUnderlyingToken(address notUnderlyingToken) public {
        cheats.assume(notUnderlyingToken != address(underlyingToken));

        uint256 amountToWithdraw = 1e18;

        cheats.expectRevert(bytes("StrategyBase.withdraw: Can only withdraw the strategy token"));
        cheats.startPrank(address(strategyManager));
        strategy.withdraw(address(this), IERC20(notUnderlyingToken), amountToWithdraw);
        cheats.stopPrank();
    }

    function testWithdrawFailsWhenSharesGreaterThanTotalShares(uint256 amountToDeposit, uint256 sharesToWithdraw) public {
        cheats.assume(amountToDeposit >= MIN_NONZERO_TOTAL_SHARES);
        testDepositWithZeroPriorBalanceAndZeroPriorShares(amountToDeposit);

        uint256 totalSharesBefore = strategy.totalShares();

        // since we are checking strictly greater than in this test
        cheats.assume(sharesToWithdraw > totalSharesBefore);

        cheats.expectRevert(bytes("StrategyBase.withdraw: amountShares must be less than or equal to totalShares"));
        cheats.startPrank(address(strategyManager));
        strategy.withdraw(address(this), underlyingToken, sharesToWithdraw);
        cheats.stopPrank();
    }

    function testWithdrawalFailsWhenTokenTransferFails() public {
        underlyingToken = new ERC20_SetTransferReverting_Mock(initialSupply, initialOwner);

        strategy = StrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(strategyImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(StrategyBase.initialize.selector, underlyingToken, pauserRegistry)
                )
            )
        );

        uint256 amountToDeposit = 1e18;
        testDepositWithZeroPriorBalanceAndZeroPriorShares(amountToDeposit);

        uint256 amountToWithdraw = 1e18;
        ERC20_SetTransferReverting_Mock(address(underlyingToken)).setTransfersRevert(true);

        cheats.expectRevert();
        cheats.startPrank(address(strategyManager));
        strategy.withdraw(address(this), underlyingToken, amountToWithdraw);
        cheats.stopPrank();
    }

    function testIntegrityOfSharesToUnderlyingWithZeroTotalShares(uint256 amountSharesToQuery) public view {
        uint256 underlyingFromShares = strategy.sharesToUnderlying(amountSharesToQuery);
        require(underlyingFromShares == amountSharesToQuery, "underlyingFromShares != amountSharesToQuery");

        uint256 underlyingFromSharesView = strategy.sharesToUnderlyingView(amountSharesToQuery);
        require(underlyingFromSharesView == amountSharesToQuery, "underlyingFromSharesView != amountSharesToQuery");
    }

    // amountSharesToQuery input is uint96 to prevent overflow
    function testIntegrityOfSharesToUnderlyingWithNonzeroTotalShares(uint256 amountToDeposit, uint256 amountToTransfer, uint96 amountSharesToQuery) public {
        // sanity check / filter
        cheats.assume(amountToDeposit <= underlyingToken.balanceOf(address(this)));
        cheats.assume(amountToDeposit >= MIN_NONZERO_TOTAL_SHARES);

        testDepositWithZeroPriorBalanceAndZeroPriorShares(amountToDeposit);

        cheats.assume(amountToTransfer <= underlyingToken.balanceOf(address(this)));
        underlyingToken.transfer(address(strategy), amountToTransfer);
        uint256 strategyBalance = underlyingToken.balanceOf(address(strategy));

        uint256 expectedValueOut = (strategyBalance * amountSharesToQuery) / strategy.totalShares();

        uint256 underlyingFromShares = strategy.sharesToUnderlying(amountSharesToQuery);
        require(underlyingFromShares == expectedValueOut, "underlyingFromShares != expectedValueOut");

        uint256 underlyingFromSharesView = strategy.sharesToUnderlyingView(amountSharesToQuery);
        require(underlyingFromSharesView == expectedValueOut, "underlyingFromSharesView != expectedValueOut");
    }


    function testIntegrityOfUnderlyingToSharesWithZeroTokenBalance(uint256 amountToDeposit, uint256 amountUnderlyingToQuery) public {
        cheats.assume(amountToDeposit >= MIN_NONZERO_TOTAL_SHARES);
        testDepositWithZeroPriorBalanceAndZeroPriorShares(amountToDeposit);

        // have the strategy transfer out all of its tokens
        cheats.startPrank(address(strategy));
        underlyingToken.transfer(address(this), underlyingToken.balanceOf(address(strategy)));
        cheats.stopPrank();

        uint256 sharesFromUnderlying = strategy.underlyingToShares(amountUnderlyingToQuery);
        require(sharesFromUnderlying == amountUnderlyingToQuery, "sharesFromUnderlying != amountUnderlyingToQuery");

        uint256 sharesFromUnderlyingView = strategy.underlyingToSharesView(amountUnderlyingToQuery);
        require(sharesFromUnderlyingView == amountUnderlyingToQuery, "sharesFromUnderlyingView != amountUnderlyingToQuery");
    }

    function testIntegrityOfUnderlyingToSharesWithZeroTotalShares(uint256 amountUnderlyingToQuery) public view {
        uint256 sharesFromUnderlying = strategy.underlyingToShares(amountUnderlyingToQuery);
        require(sharesFromUnderlying == amountUnderlyingToQuery, "sharesFromUnderlying != amountUnderlyingToQuery");

        uint256 sharesFromUnderlyingView = strategy.underlyingToSharesView(amountUnderlyingToQuery);
        require(sharesFromUnderlyingView == amountUnderlyingToQuery, "sharesFromUnderlyingView != amountUnderlyingToQuery");
    }

    // amountUnderlyingToQuery input is uint96 to prevent overflow
    function testIntegrityOfUnderlyingToSharesWithNonzeroTotalShares(uint256 amountToDeposit, uint256 amountToTransfer, uint96 amountUnderlyingToQuery) public {
        // sanity check / filter
        cheats.assume(amountToDeposit <= underlyingToken.balanceOf(address(this)));
        cheats.assume(amountToDeposit >= MIN_NONZERO_TOTAL_SHARES);

        testDepositWithZeroPriorBalanceAndZeroPriorShares(amountToDeposit);

        cheats.assume(amountToTransfer <= underlyingToken.balanceOf(address(this)));
        underlyingToken.transfer(address(strategy), amountToTransfer);
        uint256 strategyBalance = underlyingToken.balanceOf(address(strategy));

        uint256 expectedValueOut = (strategy.totalShares() * amountUnderlyingToQuery) / strategyBalance;

        uint256 sharesFromUnderlying = strategy.underlyingToShares(amountUnderlyingToQuery);
        require(sharesFromUnderlying == expectedValueOut, "sharesFromUnderlying != expectedValueOut");

        uint256 sharesFromUnderlyingView = strategy.underlyingToSharesView(amountUnderlyingToQuery);
        require(sharesFromUnderlyingView == expectedValueOut, "sharesFromUnderlyingView != expectedValueOut");
    }

}