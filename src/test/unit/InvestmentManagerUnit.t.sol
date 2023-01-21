// //SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "forge-std/Test.sol";

import "../../contracts/core/InvestmentManager.sol";
import "../../contracts/strategies/InvestmentStrategyBase.sol";
import "../../contracts/permissions/PauserRegistry.sol";
import "../mocks/DelegationMock.sol";
import "../mocks/SlasherMock.sol";
import "../mocks/EigenPodManagerMock.sol";
import "../mocks/Reenterer.sol";
import "../mocks/Reverter.sol";


import "../mocks/ERC20Mock.sol";


contract InvestmentManagerUnitTests is Test {

    Vm cheats = Vm(HEVM_ADDRESS);

    uint256 public REQUIRED_BALANCE_WEI = 31.4 ether;

    ProxyAdmin public proxyAdmin;
    PauserRegistry public pauserRegistry;

    InvestmentManager public investmentManagerImplementation;
    InvestmentManager public investmentManager;
    DelegationMock public delegationMock;
    SlasherMock public slasherMock;
    EigenPodManagerMock public eigenPodManagerMock;

    InvestmentStrategyBase public dummyStratImplementation;
    InvestmentStrategyBase public dummyStrat;

    IInvestmentStrategy public beaconChainETHStrategy;

    IERC20 public dummyToken;

    Reenterer public reenterer;

    uint256 GWEI_TO_WEI = 1e9;

    address public pauser = address(555);
    address public unpauser = address(999);

    address initialOwner = address(this);

    function setUp() virtual public {
        proxyAdmin = new ProxyAdmin();

        pauserRegistry = new PauserRegistry(pauser, unpauser);

        slasherMock = new SlasherMock();
        delegationMock = new DelegationMock();
        eigenPodManagerMock = new EigenPodManagerMock();
        investmentManagerImplementation = new InvestmentManager(delegationMock, eigenPodManagerMock, slasherMock);
        investmentManager = InvestmentManager(
            address(
                new TransparentUpgradeableProxy(
                    address(investmentManagerImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(InvestmentManager.initialize.selector, pauserRegistry, initialOwner)
                )
            )
        );
        dummyToken = new ERC20Mock();
        dummyStratImplementation = new InvestmentStrategyBase(investmentManager);
        dummyStrat = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(dummyStratImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, dummyToken, pauserRegistry)
                )
            )
        );

        beaconChainETHStrategy = investmentManager.beaconChainETHStrategy();
    }

    function testCannotReinitialize() public {
        cheats.expectRevert(bytes("Initializable: contract is already initialized"));
        investmentManager.initialize(pauserRegistry, initialOwner);
    }

    function testDepositBeaconChainETHSuccessfully(address staker, uint256 amount) public {
        // filter out zero case since it will revert with "InvestmentManager._addShares: shares should not be zero!"
        cheats.assume(amount != 0);
        uint256 sharesBefore = investmentManager.investorStratShares(staker, beaconChainETHStrategy);

        cheats.startPrank(address(investmentManager.eigenPodManager()));
        investmentManager.depositBeaconChainETH(staker, amount);
        cheats.stopPrank();

        uint256 sharesAfter = investmentManager.investorStratShares(staker, beaconChainETHStrategy);
        require(sharesAfter == sharesBefore + amount, "sharesAfter != sharesBefore + amount");
    }

    function testDepositBeaconChainETHFailsWhenNotCalledByEigenPodManager(address improperCaller) public {
        cheats.assume(improperCaller != address(eigenPodManagerMock));
        uint256 amount = 1e18;
        address staker = address(this);

        cheats.expectRevert(bytes("InvestmentManager.onlyEigenPodManager: not the eigenPodManager"));
        cheats.startPrank(address(improperCaller));
        investmentManager.depositBeaconChainETH(staker, amount);
        cheats.stopPrank();
    }

    function testDepositBeaconChainETHFailsWhenDepositsPaused() public {
        uint256 amount = 1e18;
        address staker = address(this);

        // pause deposits
        cheats.startPrank(pauser);
        investmentManager.pause(1);
        cheats.stopPrank();

        cheats.expectRevert(bytes("Pausable: index is paused"));
        cheats.startPrank(address(eigenPodManagerMock));
        investmentManager.depositBeaconChainETH(staker, amount);
        cheats.stopPrank();
    }

    function testDepositBeaconChainETHFailsWhenStakerFrozen() public {
        uint256 amount = 1e18;
        address staker = address(this);

        // freeze the staker
        slasherMock.freezeOperator(staker);

        cheats.expectRevert(bytes("InvestmentManager.onlyNotFrozen: staker has been frozen and may be subject to slashing"));
        cheats.startPrank(address(eigenPodManagerMock));
        investmentManager.depositBeaconChainETH(staker, amount);
        cheats.stopPrank();
    }

    function testDepositBeaconChainETHFailsWhenReentering() public {
        uint256 amount = 1e18;
        address staker = address(this);

        _beaconChainReentrancyTestsSetup();

        address targetToUse = address(investmentManager);
        uint256 msgValueToUse = 0;
        bytes memory calldataToUse = abi.encodeWithSelector(InvestmentManager.depositBeaconChainETH.selector, staker, amount);
        reenterer.prepare(targetToUse, msgValueToUse, calldataToUse, bytes("ReentrancyGuard: reentrant call"));

        cheats.startPrank(address(reenterer));
        investmentManager.depositBeaconChainETH(staker, amount);
        cheats.stopPrank();
    }

    function testRecordOvercommittedBeaconChainETHSuccessfully(uint256 amount_1, uint256 amount_2) public {
        // zero inputs will revert, and cannot reduce more than full amount
        cheats.assume(amount_2 <= amount_1 && amount_1 != 0 && amount_2 != 0);

        address overcommittedPodOwner = address(this);
        uint256 beaconChainETHStrategyIndex = 0;
        testDepositBeaconChainETHSuccessfully(overcommittedPodOwner, amount_1);

        uint256 sharesBefore = investmentManager.investorStratShares(overcommittedPodOwner, beaconChainETHStrategy);

        cheats.startPrank(address(eigenPodManagerMock));
        investmentManager.recordOvercommittedBeaconChainETH(overcommittedPodOwner, beaconChainETHStrategyIndex, amount_2);
        cheats.stopPrank();

        uint256 sharesAfter = investmentManager.investorStratShares(overcommittedPodOwner, beaconChainETHStrategy);
        require(sharesAfter == sharesBefore - amount_2, "sharesAfter != sharesBefore - amount");
    }

    function testRecordOvercommittedBeaconChainETHFailsWhenNotCalledByEigenPodManager(address improperCaller) public {
        // fuzzed input filtering
        cheats.assume(improperCaller != address(eigenPodManagerMock) && improperCaller != address(proxyAdmin));
        uint256 amount = 1e18;
        address staker = address(this);
        uint256 beaconChainETHStrategyIndex = 0;

        testDepositBeaconChainETHSuccessfully(staker, amount);

        cheats.expectRevert(bytes("InvestmentManager.onlyEigenPodManager: not the eigenPodManager"));
        cheats.startPrank(address(improperCaller));
        investmentManager.recordOvercommittedBeaconChainETH(staker, beaconChainETHStrategyIndex, amount);
        cheats.stopPrank();
    }

    function testRecordOvercommittedBeaconChainETHFailsWhenReentering() public {
        uint256 amount = 1e18;
        address staker = address(this);
        uint256 beaconChainETHStrategyIndex = 0;

        _beaconChainReentrancyTestsSetup();

        testDepositBeaconChainETHSuccessfully(staker, amount);        

        address targetToUse = address(investmentManager);
        uint256 msgValueToUse = 0;
        bytes memory calldataToUse = abi.encodeWithSelector(InvestmentManager.recordOvercommittedBeaconChainETH.selector, staker, beaconChainETHStrategyIndex, amount);
        reenterer.prepare(targetToUse, msgValueToUse, calldataToUse, bytes("ReentrancyGuard: reentrant call"));

        cheats.startPrank(address(reenterer));
        investmentManager.recordOvercommittedBeaconChainETH(staker, beaconChainETHStrategyIndex, amount);
        cheats.stopPrank();
    }

    function testDepositIntoStrategySuccessfully(address staker, uint256 amount) public {
        // fuzzed input filtering
        cheats.assume(staker != address(proxyAdmin));
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;

        // filter out zero case since it will revert with "InvestmentManager._addShares: shares should not be zero!"
        cheats.assume(amount != 0);
        // filter out zero address because the mock ERC20 we are using will revert on using it
        cheats.assume(staker != address(0));
        // sanity check / filter
        cheats.assume(amount <= token.balanceOf(address(this)));

        uint256 sharesBefore = investmentManager.investorStratShares(staker, strategy);
        uint256 investorStratsLengthBefore = investmentManager.investorStratsLength(staker);

        cheats.startPrank(staker);
        uint256 shares = investmentManager.depositIntoStrategy(strategy, token, amount);
        cheats.stopPrank();

        uint256 sharesAfter = investmentManager.investorStratShares(staker, strategy);
        uint256 investorStratsLengthAfter = investmentManager.investorStratsLength(staker);

        require(sharesAfter == sharesBefore + shares, "sharesAfter != sharesBefore + shares");
        if (sharesBefore == 0) {
            require(investorStratsLengthAfter == investorStratsLengthBefore + 1, "investorStratsLengthAfter != investorStratsLengthBefore + 1");
            require(investmentManager.investorStrats(staker, investorStratsLengthAfter - 1) == strategy,
                "investmentManager.investorStrats(staker, investorStratsLengthAfter - 1) != strategy");
        }
    }

    function testDepositIntoStrategySuccessfullyTwice() public {
        address staker = address(this);
        uint256 amount = 1e18;
        testDepositIntoStrategySuccessfully(staker, amount);
        testDepositIntoStrategySuccessfully(staker, amount);
    }

    function testDepositIntoStrategyFailsWhenDepositsPaused() public {
        uint256 amount = 1e18;

        // pause deposits
        cheats.startPrank(pauser);
        investmentManager.pause(1);
        cheats.stopPrank();

        cheats.expectRevert(bytes("Pausable: index is paused"));
        investmentManager.depositIntoStrategy(dummyStrat, dummyToken, amount);
    }

    function testDepositIntoStrategyFailsWhenStakerFrozen() public {
        uint256 amount = 1e18;
        address staker = address(this);

        // freeze the staker
        slasherMock.freezeOperator(staker);

        cheats.expectRevert(bytes("InvestmentManager.onlyNotFrozen: staker has been frozen and may be subject to slashing"));
        investmentManager.depositIntoStrategy(dummyStrat, dummyToken, amount);
    }

    function testDepositIntoStrategyFailsWhenReentering() public {
        uint256 amount = 1e18;

        reenterer = new Reenterer();

        reenterer.prepareReturnData(abi.encode(amount));

        address targetToUse = address(investmentManager);
        uint256 msgValueToUse = 0;
        bytes memory calldataToUse = abi.encodeWithSelector(InvestmentManager.depositIntoStrategy.selector, address(reenterer), dummyToken, amount);
        reenterer.prepare(targetToUse, msgValueToUse, calldataToUse, bytes("ReentrancyGuard: reentrant call"));

        investmentManager.depositIntoStrategy(IInvestmentStrategy(address(reenterer)), dummyToken, amount);
    }

    function testDepositIntoStrategyOnBehalfOfSuccessfully(uint256 amount) public {
        uint256 privateKey = 111111;
        address staker = cheats.addr(111111);
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;

        // filter out zero case since it will revert with "InvestmentManager._addShares: shares should not be zero!"
        cheats.assume(amount != 0);
        // sanity check / filter
        cheats.assume(amount <= token.balanceOf(address(this)));

        uint256 nonceBefore = investmentManager.nonces(staker);
        uint256 expiry = type(uint256).max;
        bytes memory signature;

        {
            bytes32 structHash = keccak256(abi.encode(investmentManager.DEPOSIT_TYPEHASH(), strategy, token, amount, nonceBefore, expiry));
            bytes32 digestHash = keccak256(abi.encodePacked("\x19\x01", investmentManager.DOMAIN_SEPARATOR(), structHash));

            (uint8 v, bytes32 r, bytes32 s) = cheats.sign(privateKey, digestHash);

            signature = abi.encodePacked(r, s, v);
        }

        uint256 sharesBefore = investmentManager.investorStratShares(staker, strategy);

        uint256 shares = investmentManager.depositIntoStrategyOnBehalfOf(strategy, token, amount, staker, expiry, signature);

        uint256 sharesAfter = investmentManager.investorStratShares(staker, strategy);
        uint256 nonceAfter = investmentManager.nonces(staker);

        require(sharesAfter == sharesBefore + shares, "sharesAfter != sharesBefore + shares");
        require(nonceAfter == nonceBefore + 1, "nonceAfter != nonceBefore + 1");
    }

    function testDepositIntoStrategyOnBehalfOfFailsWhenDepositsPaused() public {
        uint256 privateKey = 111111;
        address staker = cheats.addr(111111);
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;
        uint256 amount = 1e18;

        uint256 nonceBefore = investmentManager.nonces(staker);
        uint256 expiry = type(uint256).max;
        bytes memory signature;

        {
            bytes32 structHash = keccak256(abi.encode(investmentManager.DEPOSIT_TYPEHASH(), strategy, token, amount, nonceBefore, expiry));
            bytes32 digestHash = keccak256(abi.encodePacked("\x19\x01", investmentManager.DOMAIN_SEPARATOR(), structHash));

            (uint8 v, bytes32 r, bytes32 s) = cheats.sign(privateKey, digestHash);

            signature = abi.encodePacked(r, s, v);
        }

        uint256 sharesBefore = investmentManager.investorStratShares(staker, strategy);

        // pause deposits
        cheats.startPrank(pauser);
        investmentManager.pause(1);
        cheats.stopPrank();

        cheats.expectRevert(bytes("Pausable: index is paused"));
        investmentManager.depositIntoStrategyOnBehalfOf(strategy, token, amount, staker, expiry, signature);

        uint256 sharesAfter = investmentManager.investorStratShares(staker, strategy);
        uint256 nonceAfter = investmentManager.nonces(staker);

        require(sharesAfter == sharesBefore, "sharesAfter != sharesBefore");
        require(nonceAfter == nonceBefore, "nonceAfter != nonceBefore");
    }

    function testDepositIntoStrategyOnBehalfOfFailsWhenStakerFrozen() public {
        uint256 privateKey = 111111;
        address staker = cheats.addr(111111);
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;
        uint256 amount = 1e18;

        uint256 nonceBefore = investmentManager.nonces(staker);
        uint256 expiry = type(uint256).max;
        bytes memory signature;

        {
            bytes32 structHash = keccak256(abi.encode(investmentManager.DEPOSIT_TYPEHASH(), strategy, token, amount, nonceBefore, expiry));
            bytes32 digestHash = keccak256(abi.encodePacked("\x19\x01", investmentManager.DOMAIN_SEPARATOR(), structHash));

            (uint8 v, bytes32 r, bytes32 s) = cheats.sign(privateKey, digestHash);

            signature = abi.encodePacked(r, s, v);
        }

        uint256 sharesBefore = investmentManager.investorStratShares(staker, strategy);

        // freeze the staker
        slasherMock.freezeOperator(staker);

        cheats.expectRevert(bytes("InvestmentManager.onlyNotFrozen: staker has been frozen and may be subject to slashing"));
        investmentManager.depositIntoStrategyOnBehalfOf(strategy, token, amount, staker, expiry, signature);

        uint256 sharesAfter = investmentManager.investorStratShares(staker, strategy);
        uint256 nonceAfter = investmentManager.nonces(staker);

        require(sharesAfter == sharesBefore, "sharesAfter != sharesBefore");
        require(nonceAfter == nonceBefore, "nonceAfter != nonceBefore");
    }

    function testDepositIntoStrategyOnBehalfOfFailsWhenReentering() public {
        reenterer = new Reenterer();

        uint256 privateKey = 111111;
        address staker = cheats.addr(111111);
        IInvestmentStrategy strategy = IInvestmentStrategy(address(reenterer));
        IERC20 token = dummyToken;
        uint256 amount = 1e18;

        uint256 nonceBefore = investmentManager.nonces(staker);
        uint256 expiry = type(uint256).max;
        bytes memory signature;

        {
            bytes32 structHash = keccak256(abi.encode(investmentManager.DEPOSIT_TYPEHASH(), strategy, token, amount, nonceBefore, expiry));
            bytes32 digestHash = keccak256(abi.encodePacked("\x19\x01", investmentManager.DOMAIN_SEPARATOR(), structHash));

            (uint8 v, bytes32 r, bytes32 s) = cheats.sign(privateKey, digestHash);

            signature = abi.encodePacked(r, s, v);
        }

        uint256 sharesBefore = investmentManager.investorStratShares(staker, strategy);

        uint256 shareAmountToReturn = amount;
        reenterer.prepareReturnData(abi.encode(shareAmountToReturn));

        {
            address targetToUse = address(investmentManager);
            uint256 msgValueToUse = 0;
            bytes memory calldataToUse = abi.encodeWithSelector(InvestmentManager.depositIntoStrategy.selector, address(reenterer), dummyToken, amount);
            reenterer.prepare(targetToUse, msgValueToUse, calldataToUse, bytes("ReentrancyGuard: reentrant call"));
        }

        investmentManager.depositIntoStrategyOnBehalfOf(strategy, token, amount, staker, expiry, signature);

        uint256 sharesAfter = investmentManager.investorStratShares(staker, strategy);
        uint256 nonceAfter = investmentManager.nonces(staker);

        require(sharesAfter == sharesBefore + shareAmountToReturn, "sharesAfter != sharesBefore + shareAmountToReturn");
        require(nonceAfter == nonceBefore + 1, "nonceAfter != nonceBefore + 1");
    }

    function testDepositIntoStrategyOnBehalfOfFailsWhenSignatureExpired() public {
        uint256 privateKey = 111111;
        address staker = cheats.addr(111111);
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;
        uint256 amount = 1e18;

        uint256 nonceBefore = investmentManager.nonces(staker);
        uint256 expiry = 5555;
        // warp to 1 second after expiry
        cheats.warp(expiry + 1);
        bytes memory signature;

        {
            bytes32 structHash = keccak256(abi.encode(investmentManager.DEPOSIT_TYPEHASH(), strategy, token, amount, nonceBefore, expiry));
            bytes32 digestHash = keccak256(abi.encodePacked("\x19\x01", investmentManager.DOMAIN_SEPARATOR(), structHash));

            (uint8 v, bytes32 r, bytes32 s) = cheats.sign(privateKey, digestHash);

            signature = abi.encodePacked(r, s, v);
        }

        uint256 sharesBefore = investmentManager.investorStratShares(staker, strategy);

        cheats.expectRevert(bytes("InvestmentManager.depositIntoStrategyOnBehalfOf: signature expired"));
        investmentManager.depositIntoStrategyOnBehalfOf(strategy, token, amount, staker, expiry, signature);

        uint256 sharesAfter = investmentManager.investorStratShares(staker, strategy);
        uint256 nonceAfter = investmentManager.nonces(staker);

        require(sharesAfter == sharesBefore, "sharesAfter != sharesBefore");
        require(nonceAfter == nonceBefore, "nonceAfter != nonceBefore");
    }

    function testDepositIntoStrategyOnBehalfOfFailsWhenSignatureInvalid() public {
        uint256 privateKey = 111111;
        address staker = cheats.addr(111111);
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;
        uint256 amount = 1e18;

        uint256 nonceBefore = investmentManager.nonces(staker);
        uint256 expiry = 5555;
        bytes memory signature;

        {
            bytes32 structHash = keccak256(abi.encode(investmentManager.DEPOSIT_TYPEHASH(), strategy, token, amount, nonceBefore, expiry));
            bytes32 digestHash = keccak256(abi.encodePacked("\x19\x01", investmentManager.DOMAIN_SEPARATOR(), structHash));

            (uint8 v, bytes32 r, bytes32 s) = cheats.sign(privateKey, digestHash);

            signature = abi.encodePacked(r, s, v);
        }

        uint256 sharesBefore = investmentManager.investorStratShares(staker, strategy);

        cheats.expectRevert(bytes("InvestmentManager.depositIntoStrategyOnBehalfOf: signature not from staker"));
        // call with `notStaker` as input instead of `staker` address
        address notStaker = address(3333);
        investmentManager.depositIntoStrategyOnBehalfOf(strategy, token, amount, notStaker, expiry, signature);

        uint256 sharesAfter = investmentManager.investorStratShares(staker, strategy);
        uint256 nonceAfter = investmentManager.nonces(staker);

        require(sharesAfter == sharesBefore, "sharesAfter != sharesBefore");
        require(nonceAfter == nonceBefore, "nonceAfter != nonceBefore");
    }

    function testUndelegate() public {
        investmentManager.undelegate();
    }

    // fuzzed input amountGwei is sized-down, since it must be in GWEI and gets sized-up to be WEI
    function testQueueWithdrawalBeaconChainETHToSelf(uint128 amountGwei)
        public returns (IInvestmentManager.QueuedWithdrawal memory, bytes32 /*withdrawalRoot*/) 
    {
        // scale fuzzed amount up to be a whole amount of GWEI
        uint256 amount = uint256(amountGwei) * 1e9;
        address staker = address(this);
        address withdrawer = staker;
        IInvestmentStrategy strategy = beaconChainETHStrategy;
        IERC20 token;

        testDepositBeaconChainETHSuccessfully(staker, amount);

        bool undelegateIfPossible = false;

        (IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal, IInvestmentManager.StratsTokensShares memory sts, bytes32 withdrawalRoot) =
            _setUpQueuedWithdrawalStructSingleStrat(staker, withdrawer, token, strategy, amount);

        uint256 sharesBefore = investmentManager.investorStratShares(staker, strategy);
        uint256 nonceBefore = investmentManager.numWithdrawalsQueued(staker);

        require(!investmentManager.withdrawalRootPending(withdrawalRoot), "withdrawalRootPendingBefore is true!");

        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;
        investmentManager.queueWithdrawal(strategyIndexes, sts, withdrawer, undelegateIfPossible);

        uint256 sharesAfter = investmentManager.investorStratShares(staker, strategy);
        uint256 nonceAfter = investmentManager.numWithdrawalsQueued(staker);

        require(investmentManager.withdrawalRootPending(withdrawalRoot), "withdrawalRootPendingAfter is false!");
        require(sharesAfter == sharesBefore - amount, "sharesAfter != sharesBefore - amount");
        require(nonceAfter == nonceBefore + 1, "nonceAfter != nonceBefore + 1");

        return (queuedWithdrawal, withdrawalRoot);
    }

    function testQueueWithdrawalBeaconChainETHToDifferentAddress(address withdrawer) external {
        // filtering for test flakiness
        cheats.assume(withdrawer != address(this));

        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](2);
        IERC20[] memory tokensArray = new IERC20[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        uint256[] memory strategyIndexes = new uint256[](1);
        bool undelegateIfPossible = false;

        {
            strategyArray[0] = investmentManager.beaconChainETHStrategy();
            shareAmounts[0] = REQUIRED_BALANCE_WEI;
            strategyIndexes[0] = 0;
        }

        IInvestmentManager.StratsTokensShares memory sts = IInvestmentManager.StratsTokensShares(strategyArray, tokensArray, shareAmounts);
        cheats.expectRevert(bytes("InvestmentManager.queueWithdrawal: cannot queue a withdrawal of Beacon Chain ETH to a different address"));
        investmentManager.queueWithdrawal(strategyIndexes, sts, withdrawer, undelegateIfPossible);
    }

    function testQueueWithdrawalMultipleStrategiesWithBeaconChain() external {
        testDepositIntoStrategySuccessfully(address(this), REQUIRED_BALANCE_WEI);

        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](2);
        IERC20[] memory tokensArray = new IERC20[](2);
        uint256[] memory shareAmounts = new uint256[](2);
        uint256[] memory strategyIndexes = new uint256[](2);
        bool undelegateIfPossible = false;

        {
            strategyArray[0] = investmentManager.beaconChainETHStrategy();
            shareAmounts[0] = REQUIRED_BALANCE_WEI;
            strategyIndexes[0] = 0;
            strategyArray[1] = new InvestmentStrategyBase(investmentManager);
            shareAmounts[1] = REQUIRED_BALANCE_WEI;
            strategyIndexes[1] = 1;
        }

        IInvestmentManager.StratsTokensShares memory sts = IInvestmentManager.StratsTokensShares(strategyArray, tokensArray, shareAmounts);
        cheats.expectRevert(bytes("InvestmentManager.queueWithdrawal: cannot queue a withdrawal including Beacon Chain ETH and other tokens"));
        investmentManager.queueWithdrawal(strategyIndexes, sts, address(this), undelegateIfPossible);

        {
            strategyArray[0] = dummyStrat;
            shareAmounts[0] = 1;
            strategyIndexes[0] = 0;
            strategyArray[1] = investmentManager.beaconChainETHStrategy();
            shareAmounts[1] = REQUIRED_BALANCE_WEI;
            strategyIndexes[1] = 1;
        }
        sts = IInvestmentManager.StratsTokensShares(strategyArray, tokensArray, shareAmounts);
        cheats.expectRevert(bytes("InvestmentManager.queueWithdrawal: cannot queue a withdrawal including Beacon Chain ETH and other tokens"));
        investmentManager.queueWithdrawal(strategyIndexes, sts, address(this), undelegateIfPossible);
    }

    function testQueueWithdrawalBeaconChainEthNonWholeAmountGwei(uint256 nonWholeAmount) external {
        cheats.assume(nonWholeAmount % GWEI_TO_WEI != 0);
        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        uint256[] memory strategyIndexes = new uint256[](1);
        bool undelegateIfPossible = false;

        {
            strategyArray[0] = investmentManager.beaconChainETHStrategy();
            shareAmounts[0] = REQUIRED_BALANCE_WEI - 1243895959494;
            strategyIndexes[0] = 0;
        }

        IInvestmentManager.StratsTokensShares memory sts = IInvestmentManager.StratsTokensShares(strategyArray, tokensArray, shareAmounts);
        cheats.expectRevert(bytes("InvestmentManager.queueWithdrawal: cannot queue a withdrawal of Beacon Chain ETH for an non-whole amount of gwei"));
        investmentManager.queueWithdrawal(strategyIndexes, sts, address(this), undelegateIfPossible);
    }

    function testQueueWithdrawal_ToSelf_NotBeaconChainETH(uint256 depositAmount, uint256 withdrawalAmount, bool undelegateIfPossible) public
        returns (IInvestmentManager.QueuedWithdrawal memory, bytes32 /* withdrawalRoot */)
    {
        // filtering of fuzzed inputs
        cheats.assume(withdrawalAmount != 0 && withdrawalAmount <= depositAmount);

        address staker = address(this);
        IInvestmentStrategy strategy = dummyStrat;
        // IERC20 token = dummyToken;

        testDepositIntoStrategySuccessfully(staker, depositAmount);

        (IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal, IInvestmentManager.StratsTokensShares memory sts, bytes32 withdrawalRoot) =
            _setUpQueuedWithdrawalStructSingleStrat(staker, /*withdrawer*/ staker, dummyToken, strategy, withdrawalAmount);

        uint256 sharesBefore = investmentManager.investorStratShares(staker, strategy);
        uint256 nonceBefore = investmentManager.numWithdrawalsQueued(staker);

        require(!investmentManager.withdrawalRootPending(withdrawalRoot), "withdrawalRootPendingBefore is true!");

        {
            uint256[] memory strategyIndexes = new uint256[](1);
            strategyIndexes[0] = 0;
            investmentManager.queueWithdrawal(strategyIndexes, sts, /*withdrawer*/ staker, undelegateIfPossible);
        }

        uint256 sharesAfter = investmentManager.investorStratShares(staker, strategy);
        uint256 nonceAfter = investmentManager.numWithdrawalsQueued(staker);

        require(investmentManager.withdrawalRootPending(withdrawalRoot), "withdrawalRootPendingAfter is false!");
        require(sharesAfter == sharesBefore - withdrawalAmount, "sharesAfter != sharesBefore - withdrawalAmount");
        require(nonceAfter == nonceBefore + 1, "nonceAfter != nonceBefore + 1");

        return (queuedWithdrawal, withdrawalRoot);
    }

    function testQueueWithdrawal_ToDifferentAddress_NotBeaconChainETH(address withdrawer, uint256 amount) external {
        address staker = address(this);
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;

        testDepositIntoStrategySuccessfully(staker, amount);

        (/*IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal*/, IInvestmentManager.StratsTokensShares memory sts, bytes32 withdrawalRoot) =
            _setUpQueuedWithdrawalStructSingleStrat(staker, withdrawer, token, strategy, amount);

        uint256 sharesBefore = investmentManager.investorStratShares(staker, strategy);
        uint256 nonceBefore = investmentManager.numWithdrawalsQueued(staker);

        require(!investmentManager.withdrawalRootPending(withdrawalRoot), "withdrawalRootPendingBefore is true!");

        bool undelegateIfPossible = false;
        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;
        investmentManager.queueWithdrawal(strategyIndexes, sts, withdrawer, undelegateIfPossible);

        uint256 sharesAfter = investmentManager.investorStratShares(staker, strategy);
        uint256 nonceAfter = investmentManager.numWithdrawalsQueued(staker);

        require(investmentManager.withdrawalRootPending(withdrawalRoot), "withdrawalRootPendingAfter is false!");
        require(sharesAfter == sharesBefore - amount, "sharesAfter != sharesBefore - amount");
        require(nonceAfter == nonceBefore + 1, "nonceAfter != nonceBefore + 1");
    }


    // TODO: set up delegation for the following three tests and check afterwords
    function testQueueWithdrawal_WithdrawEverything_DontUndelegate(uint256 amount) external {
        // delegate to self
        delegationMock.delegateTo(address(this));
        require(delegationMock.isDelegated(address(this)), "delegation mock setup failed");
        bool undelegateIfPossible = false;
        // deposit and withdraw the same amount, don't undelegate
        testQueueWithdrawal_ToSelf_NotBeaconChainETH(amount, amount, undelegateIfPossible);
        require(delegationMock.isDelegated(address(this)) == !undelegateIfPossible, "undelegation mock failed");
    }

    function testQueueWithdrawal_WithdrawEverything_DoUndelegate(uint256 amount) external {
        bool undelegateIfPossible = true;
        // deposit and withdraw the same amount, do undelegate if possible
        testQueueWithdrawal_ToSelf_NotBeaconChainETH(amount, amount, undelegateIfPossible);
        require(delegationMock.isDelegated(address(this)) == !undelegateIfPossible, "undelegation mock failed");
    }

    function testQueueWithdrawal_DontWithdrawEverything_MarkUndelegateIfPossibleAsTrue(uint128 amount) external {
        bool undelegateIfPossible = true;
        // deposit and withdraw only half, do undelegate if possible
        testQueueWithdrawal_ToSelf_NotBeaconChainETH(uint256(amount) * 2, amount, undelegateIfPossible);
        require(!delegationMock.isDelegated(address(this)), "undelegation mock failed");
    }

    function testQueueWithdrawalFailsWhenStakerFrozen() public {
        address staker = address(this);
        address withdrawer = staker;
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;
        uint256 depositAmount = 1e18;
        uint256 withdrawalAmount = depositAmount;

        testDepositIntoStrategySuccessfully(staker, depositAmount);

        (/*IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal*/, IInvestmentManager.StratsTokensShares memory sts, bytes32 withdrawalRoot) =
            _setUpQueuedWithdrawalStructSingleStrat(staker, withdrawer, token, strategy, withdrawalAmount);

        uint256 sharesBefore = investmentManager.investorStratShares(staker, strategy);
        uint256 nonceBefore = investmentManager.numWithdrawalsQueued(staker);

        require(!investmentManager.withdrawalRootPending(withdrawalRoot), "withdrawalRootPendingBefore is true!");

        // freeze the staker
        slasherMock.freezeOperator(staker);

        bool undelegateIfPossible = false;
        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;
        cheats.expectRevert(bytes("InvestmentManager.onlyNotFrozen: staker has been frozen and may be subject to slashing"));
        investmentManager.queueWithdrawal(strategyIndexes, sts, withdrawer, undelegateIfPossible);

        uint256 sharesAfter = investmentManager.investorStratShares(address(this), strategy);
        uint256 nonceAfter = investmentManager.numWithdrawalsQueued(address(this));

        require(!investmentManager.withdrawalRootPending(withdrawalRoot), "withdrawalRootPendingAfter is true!");
        require(sharesAfter == sharesBefore, "sharesAfter != sharesBefore");
        require(nonceAfter == nonceBefore, "nonceAfter != nonceBefore");
    }

    function testCompleteQueuedWithdrawal_ReceiveAsTokensMarkedFalse() external {
        address staker = address(this);
        uint256 depositAmount = 1e18;
        uint256 withdrawalAmount = 1e18;
        bool undelegateIfPossible = false;
        IInvestmentStrategy strategy = dummyStrat;

        testQueueWithdrawal_ToSelf_NotBeaconChainETH(depositAmount, withdrawalAmount, undelegateIfPossible);

        IInvestmentManager.StratsTokensShares memory sts;
        {
            IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
            IERC20[] memory tokensArray = new IERC20[](1);
            uint256[] memory shareAmounts = new uint256[](1);
            strategyArray[0] = strategy;
            shareAmounts[0] = withdrawalAmount;
            tokensArray[0] = dummyToken;
            sts = IInvestmentManager.StratsTokensShares(strategyArray, tokensArray, shareAmounts);
        }

        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;

        IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal;

        {
            uint256 nonce = investmentManager.numWithdrawalsQueued(staker);

            IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce = IInvestmentManager.WithdrawerAndNonce({
                withdrawer: staker,
                nonce: (uint96(nonce) - 1)
            });
            queuedWithdrawal = 
                IInvestmentManager.QueuedWithdrawal({
                    strategies: sts.strategies,
                    tokens: sts.tokens,
                    shares: sts.shares,
                    depositor: staker,
                    withdrawerAndNonce: withdrawerAndNonce,
                    withdrawalStartBlock: uint32(block.number),
                    delegatedAddress: investmentManager.delegation().delegatedTo(staker)
                }
            );
        }

        uint256 sharesBefore = investmentManager.investorStratShares(address(this), strategy);
        uint256 balanceBefore = dummyToken.balanceOf(address(staker));

        uint256 middlewareTimesIndex = 0;
        bool receiveAsTokens = false;
        investmentManager.completeQueuedWithdrawal(queuedWithdrawal, middlewareTimesIndex, receiveAsTokens);

        uint256 sharesAfter = investmentManager.investorStratShares(address(this), strategy);
        uint256 balanceAfter = dummyToken.balanceOf(address(staker));

        require(sharesAfter == sharesBefore + withdrawalAmount, "sharesAfter != sharesBefore + withdrawalAmount");
        require(balanceAfter == balanceBefore, "balanceAfter != balanceBefore");
    }

    function testCompleteQueuedWithdrawal_ReceiveAsTokensMarkedTrue_NotWithdrawingBeaconChainETH() external {
        address staker = address(this);
        uint256 depositAmount = 1e18;
        uint256 withdrawalAmount = 1e18;
        bool undelegateIfPossible = false;
        IInvestmentStrategy strategy = dummyStrat;

        testQueueWithdrawal_ToSelf_NotBeaconChainETH(depositAmount, withdrawalAmount, undelegateIfPossible);

        IInvestmentManager.StratsTokensShares memory sts;
        {
            IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
            IERC20[] memory tokensArray = new IERC20[](1);
            uint256[] memory shareAmounts = new uint256[](1);
            strategyArray[0] = strategy;
            shareAmounts[0] = withdrawalAmount;
            tokensArray[0] = dummyToken;
            sts = IInvestmentManager.StratsTokensShares(strategyArray, tokensArray, shareAmounts);
        }

        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;

        IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal;

        {
            uint256 nonce = investmentManager.numWithdrawalsQueued(staker);

            IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce = IInvestmentManager.WithdrawerAndNonce({
                withdrawer: staker,
                nonce: (uint96(nonce) - 1)
            });
            queuedWithdrawal = 
                IInvestmentManager.QueuedWithdrawal({
                    strategies: sts.strategies,
                    tokens: sts.tokens,
                    shares: sts.shares,
                    depositor: staker,
                    withdrawerAndNonce: withdrawerAndNonce,
                    withdrawalStartBlock: uint32(block.number),
                    delegatedAddress: investmentManager.delegation().delegatedTo(staker)
                }
            );
        }

        uint256 sharesBefore = investmentManager.investorStratShares(staker, strategy);
        uint256 balanceBefore = dummyToken.balanceOf(address(staker));

        uint256 middlewareTimesIndex = 0;
        bool receiveAsTokens = true;
        investmentManager.completeQueuedWithdrawal(queuedWithdrawal, middlewareTimesIndex, receiveAsTokens);

        uint256 sharesAfter = investmentManager.investorStratShares(staker, strategy);
        uint256 balanceAfter = dummyToken.balanceOf(address(staker));

        require(sharesAfter == sharesBefore, "sharesAfter != sharesBefore");
        require(balanceAfter == balanceBefore + withdrawalAmount, "balanceAfter != balanceBefore + withdrawalAmount");
    }

    function testCompleteQueuedWithdrawal_ReceiveAsTokensMarkedTrue_WithdrawingBeaconChainETH() external {
        address staker = address(this);
        uint256 withdrawalAmount = 1e18;
        IInvestmentStrategy strategy = beaconChainETHStrategy;

        // withdrawalAmount is converted to GWEI here
        testQueueWithdrawalBeaconChainETHToSelf(uint128(withdrawalAmount / 1e9));

        IInvestmentManager.StratsTokensShares memory sts;
        {
            IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
            IERC20[] memory tokensArray = new IERC20[](1);
            uint256[] memory shareAmounts = new uint256[](1);
            strategyArray[0] = strategy;
            shareAmounts[0] = withdrawalAmount;
            sts = IInvestmentManager.StratsTokensShares(strategyArray, tokensArray, shareAmounts);
        }

        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;

        IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal;

        {
            uint256 nonce = investmentManager.numWithdrawalsQueued(staker);

            IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce = IInvestmentManager.WithdrawerAndNonce({
                withdrawer: staker,
                nonce: (uint96(nonce) - 1)
            });
            queuedWithdrawal = 
                IInvestmentManager.QueuedWithdrawal({
                    strategies: sts.strategies,
                    tokens: sts.tokens,
                    shares: sts.shares,
                    depositor: staker,
                    withdrawerAndNonce: withdrawerAndNonce,
                    withdrawalStartBlock: uint32(block.number),
                    delegatedAddress: investmentManager.delegation().delegatedTo(staker)
                }
            );
        }

        uint256 sharesBefore = investmentManager.investorStratShares(staker, strategy);
        // uint256 balanceBefore = address(this).balance;

        uint256 middlewareTimesIndex = 0;
        bool receiveAsTokens = true;
        investmentManager.completeQueuedWithdrawal(queuedWithdrawal, middlewareTimesIndex, receiveAsTokens);

        uint256 sharesAfter = investmentManager.investorStratShares(staker, strategy);
        // uint256 balanceAfter = address(this).balance;

        require(sharesAfter == sharesBefore, "sharesAfter != sharesBefore");
        // require(balanceAfter == balanceBefore + withdrawalAmount, "balanceAfter != balanceBefore + withdrawalAmount");
        // TODO: make EigenPodManagerMock do something so we can verify that it gets called appropriately?
    }

    function testCompleteQueuedWithdrawalFailsWhenWithdrawalsPaused() external {
        address staker = address(this);
        uint256 depositAmount = 1e18;
        uint256 withdrawalAmount = 1e18;
        bool undelegateIfPossible = false;

        (IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal, /*bytes32 withdrawalRoot*/) =
            testQueueWithdrawal_ToSelf_NotBeaconChainETH(depositAmount, withdrawalAmount, undelegateIfPossible);

        IInvestmentStrategy strategy = queuedWithdrawal.strategies[0];

        uint256 sharesBefore = investmentManager.investorStratShares(address(this), strategy);
        uint256 balanceBefore = dummyToken.balanceOf(address(staker));

        uint256 middlewareTimesIndex = 0;
        bool receiveAsTokens = false;

        // pause withdrawals
        cheats.startPrank(pauser);
        investmentManager.pause(2);
        cheats.stopPrank();

        cheats.expectRevert(bytes("Pausable: index is paused"));
        investmentManager.completeQueuedWithdrawal(queuedWithdrawal, middlewareTimesIndex, receiveAsTokens);

        uint256 sharesAfter = investmentManager.investorStratShares(address(this), strategy);
        uint256 balanceAfter = dummyToken.balanceOf(address(staker));

        require(sharesAfter == sharesBefore, "sharesAfter != sharesBefore");
        require(balanceAfter == balanceBefore, "balanceAfter != balanceBefore");
    }

    function testCompleteQueuedWithdrawalFailsWhenDelegatedAddressFrozen() external {
        address staker = address(this);
        uint256 depositAmount = 1e18;
        uint256 withdrawalAmount = 1e18;
        bool undelegateIfPossible = false;

        (IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal, /*bytes32 withdrawalRoot*/) =
            testQueueWithdrawal_ToSelf_NotBeaconChainETH(depositAmount, withdrawalAmount, undelegateIfPossible);

        IInvestmentStrategy strategy = queuedWithdrawal.strategies[0];

        uint256 sharesBefore = investmentManager.investorStratShares(address(this), strategy);
        uint256 balanceBefore = dummyToken.balanceOf(address(staker));

        uint256 middlewareTimesIndex = 0;
        bool receiveAsTokens = false;

        // freeze the delegatedAddress
        slasherMock.freezeOperator(investmentManager.delegation().delegatedTo(staker));

        cheats.expectRevert(bytes("InvestmentManager.onlyNotFrozen: staker has been frozen and may be subject to slashing"));
        investmentManager.completeQueuedWithdrawal(queuedWithdrawal, middlewareTimesIndex, receiveAsTokens);

        uint256 sharesAfter = investmentManager.investorStratShares(address(this), strategy);
        uint256 balanceAfter = dummyToken.balanceOf(address(staker));

        require(sharesAfter == sharesBefore, "sharesAfter != sharesBefore");
        require(balanceAfter == balanceBefore, "balanceAfter != balanceBefore");
    }

    function testCompleteQueuedWithdrawalFailsWhenAttemptingReentrancy() external {
        // replace dummyStrat with Reenterer contract
        reenterer = new Reenterer();
        dummyStrat = InvestmentStrategyBase(address(reenterer));

        address staker = address(this);
        uint256 depositAmount = 1e18;
        uint256 withdrawalAmount = 1e18;
        bool undelegateIfPossible = false;
        IInvestmentStrategy strategy = dummyStrat;

        reenterer.prepareReturnData(abi.encode(depositAmount));

        testQueueWithdrawal_ToSelf_NotBeaconChainETH(depositAmount, withdrawalAmount, undelegateIfPossible);

        IInvestmentManager.StratsTokensShares memory sts;
        {
            IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
            IERC20[] memory tokensArray = new IERC20[](1);
            uint256[] memory shareAmounts = new uint256[](1);
            strategyArray[0] = strategy;
            shareAmounts[0] = withdrawalAmount;
            tokensArray[0] = dummyToken;
            sts = IInvestmentManager.StratsTokensShares(strategyArray, tokensArray, shareAmounts);
        }

        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;

        IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal;

        {
            uint256 nonce = investmentManager.numWithdrawalsQueued(staker);

            IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce = IInvestmentManager.WithdrawerAndNonce({
                withdrawer: staker,
                nonce: (uint96(nonce) - 1)
            });
            queuedWithdrawal = 
                IInvestmentManager.QueuedWithdrawal({
                    strategies: sts.strategies,
                    tokens: sts.tokens,
                    shares: sts.shares,
                    depositor: staker,
                    withdrawerAndNonce: withdrawerAndNonce,
                    withdrawalStartBlock: uint32(block.number),
                    delegatedAddress: investmentManager.delegation().delegatedTo(staker)
                }
            );
        }

        uint256 middlewareTimesIndex = 0;
        bool receiveAsTokens = false;

        address targetToUse = address(investmentManager);
        uint256 msgValueToUse = 0;
        bytes memory calldataToUse = abi.encodeWithSelector(InvestmentManager.completeQueuedWithdrawal.selector, queuedWithdrawal, middlewareTimesIndex, receiveAsTokens);
        reenterer.prepare(targetToUse, msgValueToUse, calldataToUse, bytes("ReentrancyGuard: reentrant call"));

        investmentManager.completeQueuedWithdrawal(queuedWithdrawal, middlewareTimesIndex, receiveAsTokens);
    }

    function testCompleteQueuedWithdrawalFailsWhenWithdrawalDoesNotExist() external {
        address staker = address(this);
        uint256 withdrawalAmount = 1e18;
        IInvestmentStrategy strategy = dummyStrat;

        IInvestmentManager.StratsTokensShares memory sts;
        {
            IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
            IERC20[] memory tokensArray = new IERC20[](1);
            uint256[] memory shareAmounts = new uint256[](1);
            strategyArray[0] = strategy;
            shareAmounts[0] = withdrawalAmount;
            tokensArray[0] = dummyToken;
            sts = IInvestmentManager.StratsTokensShares(strategyArray, tokensArray, shareAmounts);
        }

        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;

        IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal;

        {
            IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce = IInvestmentManager.WithdrawerAndNonce({
                withdrawer: staker,
                nonce: 0
            });
            queuedWithdrawal = 
                IInvestmentManager.QueuedWithdrawal({
                    strategies: sts.strategies,
                    tokens: sts.tokens,
                    shares: sts.shares,
                    depositor: staker,
                    withdrawerAndNonce: withdrawerAndNonce,
                    withdrawalStartBlock: uint32(block.number),
                    delegatedAddress: investmentManager.delegation().delegatedTo(staker)
                }
            );
        }

        uint256 sharesBefore = investmentManager.investorStratShares(address(this), strategy);
        uint256 balanceBefore = dummyToken.balanceOf(address(staker));

        uint256 middlewareTimesIndex = 0;
        bool receiveAsTokens = false;

        cheats.expectRevert(bytes("InvestmentManager.completeQueuedWithdrawal: withdrawal is not pending"));
        investmentManager.completeQueuedWithdrawal(queuedWithdrawal, middlewareTimesIndex, receiveAsTokens);

        uint256 sharesAfter = investmentManager.investorStratShares(address(this), strategy);
        uint256 balanceAfter = dummyToken.balanceOf(address(staker));

        require(sharesAfter == sharesBefore, "sharesAfter != sharesBefore");
        require(balanceAfter == balanceBefore, "balanceAfter != balanceBefore");
    }

    function testCompleteQueuedWithdrawalFailsWhenCanWithdrawReturnsFalse() external {
        address staker = address(this);
        uint256 depositAmount = 1e18;
        uint256 withdrawalAmount = 1e18;
        bool undelegateIfPossible = false;

        (IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal, /*bytes32 withdrawalRoot*/) =
            testQueueWithdrawal_ToSelf_NotBeaconChainETH(depositAmount, withdrawalAmount, undelegateIfPossible);

        IInvestmentStrategy strategy = queuedWithdrawal.strategies[0];

        uint256 sharesBefore = investmentManager.investorStratShares(address(this), strategy);
        uint256 balanceBefore = dummyToken.balanceOf(address(staker));

        uint256 middlewareTimesIndex = 0;
        bool receiveAsTokens = false;

        // prepare mock
        slasherMock.setCanWithdrawResponse(false);

        cheats.expectRevert(bytes("InvestmentManager.completeQueuedWithdrawal: shares pending withdrawal are still slashable"));
        investmentManager.completeQueuedWithdrawal(queuedWithdrawal, middlewareTimesIndex, receiveAsTokens);

        uint256 sharesAfter = investmentManager.investorStratShares(address(this), strategy);
        uint256 balanceAfter = dummyToken.balanceOf(address(staker));

        require(sharesAfter == sharesBefore, "sharesAfter != sharesBefore");
        require(balanceAfter == balanceBefore, "balanceAfter != balanceBefore");
    }

    function testCompleteQueuedWithdrawalFailsWhenNotCallingFromWithdrawerAddress() external {
        address staker = address(this);
        uint256 depositAmount = 1e18;
        uint256 withdrawalAmount = 1e18;
        bool undelegateIfPossible = false;

        (IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal, /*bytes32 withdrawalRoot*/) =
            testQueueWithdrawal_ToSelf_NotBeaconChainETH(depositAmount, withdrawalAmount, undelegateIfPossible);

        IInvestmentStrategy strategy = queuedWithdrawal.strategies[0];

        uint256 sharesBefore = investmentManager.investorStratShares(address(this), strategy);
        uint256 balanceBefore = dummyToken.balanceOf(address(staker));

        uint256 middlewareTimesIndex = 0;
        bool receiveAsTokens = false;

        cheats.startPrank(address(123456));
        cheats.expectRevert(bytes("InvestmentManager.completeQueuedWithdrawal: only specified withdrawer can complete a queued withdrawal"));
        investmentManager.completeQueuedWithdrawal(queuedWithdrawal, middlewareTimesIndex, receiveAsTokens);
        cheats.stopPrank();

        uint256 sharesAfter = investmentManager.investorStratShares(address(this), strategy);
        uint256 balanceAfter = dummyToken.balanceOf(address(staker));

        require(sharesAfter == sharesBefore, "sharesAfter != sharesBefore");
        require(balanceAfter == balanceBefore, "balanceAfter != balanceBefore");
    }

    function testCompleteQueuedWithdrawalFailsWhenTryingToCompleteSameWithdrawal2X() external {
        address staker = address(this);
        uint256 depositAmount = 1e18;
        uint256 withdrawalAmount = 1e18;
        bool undelegateIfPossible = false;

        (IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal, /*bytes32 withdrawalRoot*/) =
            testQueueWithdrawal_ToSelf_NotBeaconChainETH(depositAmount, withdrawalAmount, undelegateIfPossible);

        IInvestmentStrategy strategy = queuedWithdrawal.strategies[0];

        uint256 sharesBefore = investmentManager.investorStratShares(address(this), strategy);
        uint256 balanceBefore = dummyToken.balanceOf(address(staker));

        uint256 middlewareTimesIndex = 0;
        bool receiveAsTokens = false;

        investmentManager.completeQueuedWithdrawal(queuedWithdrawal, middlewareTimesIndex, receiveAsTokens);

        uint256 sharesAfter = investmentManager.investorStratShares(address(this), strategy);
        uint256 balanceAfter = dummyToken.balanceOf(address(staker));

        require(sharesAfter == sharesBefore + withdrawalAmount, "sharesAfter != sharesBefore + withdrawalAmount");
        require(balanceAfter == balanceBefore, "balanceAfter != balanceBefore");

        // try to complete same withdrawal again
        cheats.expectRevert(bytes("InvestmentManager.completeQueuedWithdrawal: withdrawal is not pending"));
        investmentManager.completeQueuedWithdrawal(queuedWithdrawal, middlewareTimesIndex, receiveAsTokens);
    }

    function testSlashSharesNotBeaconChainETHFuzzed(uint64 withdrawalAmount) external {
        address staker = address(this);
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;

        {
            uint256 depositAmount = 1e18;
            // filter fuzzed input
            cheats.assume(withdrawalAmount != 0 && withdrawalAmount <= depositAmount);
            testDepositIntoStrategySuccessfully(staker, depositAmount);
        }

        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        strategyArray[0] = strategy;
        tokensArray[0] = token;
        shareAmounts[0] = uint256(withdrawalAmount);

        // freeze the staker
        slasherMock.freezeOperator(staker);

        address slashedAddress = address(this);
        address recipient = address(333);
        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;

        uint256 sharesBefore = investmentManager.investorStratShares(staker, strategy);
        uint256 investorStratsLengthBefore = investmentManager.investorStratsLength(staker);
        uint256 balanceBefore = dummyToken.balanceOf(recipient);

        cheats.startPrank(investmentManager.owner());
        investmentManager.slashShares(slashedAddress, recipient, strategyArray, tokensArray, strategyIndexes, shareAmounts);
        cheats.stopPrank();

        uint256 sharesAfter = investmentManager.investorStratShares(staker, strategy);
        uint256 investorStratsLengthAfter = investmentManager.investorStratsLength(staker);
        uint256 balanceAfter = dummyToken.balanceOf(recipient);

        require(sharesAfter == sharesBefore - uint256(withdrawalAmount), "sharesAfter != sharesBefore - uint256(withdrawalAmount)");
        require(balanceAfter == balanceBefore + uint256(withdrawalAmount), "balanceAfter != balanceBefore + uint256(withdrawalAmount)");
        if (sharesAfter == 0) {
            require(investorStratsLengthAfter == investorStratsLengthBefore - 1, "investorStratsLengthAfter != investorStratsLengthBefore - 1");
        }
    }

    function testSlashSharesNotBeaconChainETH() external {
        uint256 amount = 1e18;
        address staker = address(this);
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;

        testDepositIntoStrategySuccessfully(staker, amount);

        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        strategyArray[0] = strategy;
        tokensArray[0] = token;
        shareAmounts[0] = amount;

        // freeze the staker
        slasherMock.freezeOperator(staker);

        address slashedAddress = address(this);
        address recipient = address(333);
        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;

        uint256 sharesBefore = investmentManager.investorStratShares(staker, strategy);
        uint256 investorStratsLengthBefore = investmentManager.investorStratsLength(staker);
        uint256 balanceBefore = dummyToken.balanceOf(recipient);

        cheats.startPrank(investmentManager.owner());
        investmentManager.slashShares(slashedAddress, recipient, strategyArray, tokensArray, strategyIndexes, shareAmounts);
        cheats.stopPrank();

        uint256 sharesAfter = investmentManager.investorStratShares(staker, strategy);
        uint256 investorStratsLengthAfter = investmentManager.investorStratsLength(staker);
        uint256 balanceAfter = dummyToken.balanceOf(recipient);

        require(sharesAfter == sharesBefore - amount, "sharesAfter != sharesBefore - amount");
        require(balanceAfter == balanceBefore + amount, "balanceAfter != balanceBefore + amount");
        require(sharesAfter == 0, "sharesAfter != 0");
        require(investorStratsLengthAfter == investorStratsLengthBefore - 1, "investorStratsLengthAfter != investorStratsLengthBefore - 1");
    }

    function testSlashSharesBeaconChainETH() external {
        uint256 amount = 1e18;
        address staker = address(this);
        IInvestmentStrategy strategy = beaconChainETHStrategy;
        IERC20 token;

        testDepositBeaconChainETHSuccessfully(staker, amount);

        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        strategyArray[0] = strategy;
        tokensArray[0] = token;
        shareAmounts[0] = amount;

        // freeze the staker
        slasherMock.freezeOperator(staker);

        address slashedAddress = address(this);
        address recipient = address(333);
        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;

        cheats.startPrank(investmentManager.owner());
        investmentManager.slashShares(slashedAddress, recipient, strategyArray, tokensArray, strategyIndexes, shareAmounts);
        cheats.stopPrank();
    }

    function testSlashSharesMixIncludingBeaconChainETH() external {
        uint256 amount = 1e18;
        address staker = address(this);
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;

        testDepositIntoStrategySuccessfully(staker, amount);
        testDepositBeaconChainETHSuccessfully(staker, amount);

        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](2);
        IERC20[] memory tokensArray = new IERC20[](2);
        uint256[] memory shareAmounts = new uint256[](2);
        strategyArray[0] = strategy;
        tokensArray[0] = token;
        shareAmounts[0] = amount;
        strategyArray[1] = beaconChainETHStrategy;
        tokensArray[1] = token;
        shareAmounts[1] = amount;

        // freeze the staker
        slasherMock.freezeOperator(staker);

        address slashedAddress = address(this);
        address recipient = address(333);
        uint256[] memory strategyIndexes = new uint256[](2);
        strategyIndexes[0] = 0;
        // this index is also zero, since the other strategy will be removed!
        strategyIndexes[1] = 0;

        uint256 sharesBefore = investmentManager.investorStratShares(staker, strategy);
        uint256 balanceBefore = dummyToken.balanceOf(recipient);

        cheats.startPrank(investmentManager.owner());
        investmentManager.slashShares(slashedAddress, recipient, strategyArray, tokensArray, strategyIndexes, shareAmounts);
        cheats.stopPrank();

        uint256 sharesAfter = investmentManager.investorStratShares(staker, strategy);
        uint256 balanceAfter = dummyToken.balanceOf(recipient);

        require(sharesAfter == sharesBefore - amount, "sharesAfter != sharesBefore - amount");
        require(balanceAfter == balanceBefore + amount, "balanceAfter != balanceBefore + amount");
    }

    function testSlashSharesRevertsWhenCalledByNotOwner() external {
        uint256 amount = 1e18;
        address staker = address(this);
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;

        testDepositIntoStrategySuccessfully(staker, amount);

        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        strategyArray[0] = strategy;
        tokensArray[0] = token;
        shareAmounts[0] = amount;

        // freeze the staker
        slasherMock.freezeOperator(staker);

        address slashedAddress = address(this);
        address recipient = address(333);
        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;

        // recipient is not the owner
        cheats.startPrank(recipient);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        investmentManager.slashShares(slashedAddress, recipient, strategyArray, tokensArray, strategyIndexes, shareAmounts);
        cheats.stopPrank();
    }

    function testSlashSharesRevertsWhenStakerNotFrozen() external {
        uint256 amount = 1e18;
        address staker = address(this);
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;

        testDepositIntoStrategySuccessfully(staker, amount);

        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        strategyArray[0] = strategy;
        tokensArray[0] = token;
        shareAmounts[0] = amount;

        address slashedAddress = address(this);
        address recipient = address(333);
        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;

        cheats.startPrank(investmentManager.owner());
        cheats.expectRevert(bytes("InvestmentManager.onlyFrozen: staker has not been frozen"));
        investmentManager.slashShares(slashedAddress, recipient, strategyArray, tokensArray, strategyIndexes, shareAmounts);
        cheats.stopPrank();
    }

    function testSlashSharesRevertsWhenAttemptingReentrancy() external {
        // replace dummyStrat with Reenterer contract
        reenterer = new Reenterer();
        dummyStrat = InvestmentStrategyBase(address(reenterer));

        uint256 amount = 1e18;
        address staker = address(this);
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;

        reenterer.prepareReturnData(abi.encode(amount));

        testDepositIntoStrategySuccessfully(staker, amount);
        testDepositBeaconChainETHSuccessfully(staker, amount);

        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](2);
        IERC20[] memory tokensArray = new IERC20[](2);
        uint256[] memory shareAmounts = new uint256[](2);
        strategyArray[0] = strategy;
        tokensArray[0] = token;
        shareAmounts[0] = amount;
        strategyArray[1] = beaconChainETHStrategy;
        tokensArray[1] = token;
        shareAmounts[1] = amount;

        // freeze the staker
        slasherMock.freezeOperator(staker);

        address slashedAddress = address(this);
        address recipient = address(333);
        uint256[] memory strategyIndexes = new uint256[](2);
        strategyIndexes[0] = 0;
        // this index is also zero, since the other strategy will be removed!
        strategyIndexes[1] = 0;

        // transfer investmentManager's ownership to the reenterer
        cheats.startPrank(investmentManager.owner());
        investmentManager.transferOwnership(address(reenterer));
        cheats.stopPrank();

        // prepare for reentrant call, expecting revert for reentrancy
        address targetToUse = address(investmentManager);
        uint256 msgValueToUse = 0;
        bytes memory calldataToUse =
            abi.encodeWithSelector(InvestmentManager.slashShares.selector, slashedAddress, recipient, strategyArray, tokensArray, strategyIndexes, shareAmounts);
        reenterer.prepare(targetToUse, msgValueToUse, calldataToUse, bytes("ReentrancyGuard: reentrant call"));

        cheats.startPrank(investmentManager.owner());
        investmentManager.slashShares(slashedAddress, recipient, strategyArray, tokensArray, strategyIndexes, shareAmounts);
        cheats.stopPrank();
    }

    function testSlashQueuedWithdrawalNotBeaconChainETH() external {
        address recipient = address(333);
        uint256 depositAmount = 1e18;
        uint256 withdrawalAmount = depositAmount;
        bool undelegateIfPossible = false;

        (IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal, bytes32 withdrawalRoot) =
            testQueueWithdrawal_ToSelf_NotBeaconChainETH(depositAmount, withdrawalAmount, undelegateIfPossible);

        uint256 balanceBefore = dummyToken.balanceOf(address(recipient));

        // slash the delegatedOperator
        slasherMock.freezeOperator(queuedWithdrawal.delegatedAddress);

        cheats.startPrank(investmentManager.owner());
        investmentManager.slashQueuedWithdrawal(recipient, queuedWithdrawal);
        cheats.stopPrank();

        uint256 balanceAfter = dummyToken.balanceOf(address(recipient));

        require(balanceAfter == balanceBefore + withdrawalAmount, "balanceAfter != balanceBefore + withdrawalAmount");
        require(!investmentManager.withdrawalRootPending(withdrawalRoot), "withdrawalRootPendingAfter is true!");
    }

    function testSlashQueuedWithdrawalBeaconChainETH() external {
        address recipient = address(333);
        uint256 amount = 1e18;

        (IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal, bytes32 withdrawalRoot) =
            // convert wei to gwei for test input
            testQueueWithdrawalBeaconChainETHToSelf(uint128(amount / 1e9));

        // slash the delegatedOperator
        slasherMock.freezeOperator(queuedWithdrawal.delegatedAddress);

        cheats.startPrank(investmentManager.owner());
        investmentManager.slashQueuedWithdrawal(recipient, queuedWithdrawal);
        cheats.stopPrank();

        withdrawalRoot = investmentManager.calculateWithdrawalRoot(queuedWithdrawal);
        require(!investmentManager.withdrawalRootPending(withdrawalRoot), "withdrawalRootPendingAfter is true!");

        // TODO: add to EigenPodManager mock so it appropriately checks the call to eigenPodManager.withdrawRestakedBeaconChainETH
    }

    function testSlashQueuedWithdrawalFailsWhenNotCallingFromOwnerAddress() external {
        address recipient = address(333);
        uint256 depositAmount = 1e18;
        uint256 withdrawalAmount = depositAmount;
        bool undelegateIfPossible = false;

        (IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal, bytes32 withdrawalRoot) =
            testQueueWithdrawal_ToSelf_NotBeaconChainETH(depositAmount, withdrawalAmount, undelegateIfPossible);

        uint256 balanceBefore = dummyToken.balanceOf(address(recipient));

        // slash the delegatedOperator
        slasherMock.freezeOperator(queuedWithdrawal.delegatedAddress);

        // recipient is not investmentManager.owner()
        cheats.startPrank(recipient);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        investmentManager.slashQueuedWithdrawal(recipient, queuedWithdrawal);
        cheats.stopPrank();

        uint256 balanceAfter = dummyToken.balanceOf(address(recipient));

        require(balanceAfter == balanceBefore, "balanceAfter != balanceBefore");
        require(investmentManager.withdrawalRootPending(withdrawalRoot), "withdrawalRootPendingAfter is false");
    }

    function testSlashQueuedWithdrawalFailsWhenDelegatedAddressNotFrozen() external {
        address recipient = address(333);
        uint256 depositAmount = 1e18;
        uint256 withdrawalAmount = depositAmount;
        bool undelegateIfPossible = false;

        (IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal, bytes32 withdrawalRoot) =
            testQueueWithdrawal_ToSelf_NotBeaconChainETH(depositAmount, withdrawalAmount, undelegateIfPossible);

        uint256 balanceBefore = dummyToken.balanceOf(address(recipient));

        cheats.startPrank(investmentManager.owner());
        cheats.expectRevert(bytes("InvestmentManager.onlyFrozen: staker has not been frozen"));
        investmentManager.slashQueuedWithdrawal(recipient, queuedWithdrawal);
        cheats.stopPrank();

        uint256 balanceAfter = dummyToken.balanceOf(address(recipient));

        require(balanceAfter == balanceBefore, "balanceAfter != balanceBefore");
        require(investmentManager.withdrawalRootPending(withdrawalRoot), "withdrawalRootPendingAfter is false");
    }

    function testSlashQueuedWithdrawalFailsWhenAttemptingReentrancy() external {
        // replace dummyStrat with Reenterer contract
        reenterer = new Reenterer();
        dummyStrat = InvestmentStrategyBase(address(reenterer));

        address staker = address(this);
        address recipient = address(333);
        uint256 depositAmount = 1e18;
        uint256 withdrawalAmount = depositAmount;
        bool undelegateIfPossible = false;

        reenterer.prepareReturnData(abi.encode(depositAmount));

        (IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal, /*bytes32 withdrawalRoot*/) =
            testQueueWithdrawal_ToSelf_NotBeaconChainETH(depositAmount, withdrawalAmount, undelegateIfPossible);

        // freeze the delegatedAddress
        slasherMock.freezeOperator(investmentManager.delegation().delegatedTo(staker));

        // transfer investmentManager's ownership to the reenterer
        cheats.startPrank(investmentManager.owner());
        investmentManager.transferOwnership(address(reenterer));
        cheats.stopPrank();

        // prepare for reentrant call, expecting revert for reentrancy
        address targetToUse = address(investmentManager);
        uint256 msgValueToUse = 0;
        bytes memory calldataToUse =
            abi.encodeWithSelector(InvestmentManager.slashQueuedWithdrawal.selector, recipient, queuedWithdrawal);
        reenterer.prepare(targetToUse, msgValueToUse, calldataToUse, bytes("ReentrancyGuard: reentrant call"));

        cheats.startPrank(investmentManager.owner());
        investmentManager.slashQueuedWithdrawal(recipient, queuedWithdrawal);
        cheats.stopPrank();
    }

    function testSlashQueuedWithdrawalFailsWhenWithdrawalDoesNotExist() external {
        address recipient = address(333);
        uint256 amount = 1e18;

        (IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal, /*bytes32 withdrawalRoot*/) =
            // convert wei to gwei for test input
            testQueueWithdrawalBeaconChainETHToSelf(uint128(amount / 1e9));

        // slash the delegatedOperator
        slasherMock.freezeOperator(queuedWithdrawal.delegatedAddress);

        // modify the queuedWithdrawal data so the root won't exist
        queuedWithdrawal.shares[0] = (amount * 2);

        cheats.startPrank(investmentManager.owner());
        cheats.expectRevert(bytes("InvestmentManager.slashQueuedWithdrawal: withdrawal is not pending"));
        investmentManager.slashQueuedWithdrawal(recipient, queuedWithdrawal);
        cheats.stopPrank();
    }

    function test_addSharesRevertsWhenSharesIsZero() external {
        // replace dummyStrat with Reenterer contract
        reenterer = new Reenterer();
        dummyStrat = InvestmentStrategyBase(address(reenterer));

        address staker = address(this);
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;
        uint256 amount = 1e18;

        reenterer.prepareReturnData(abi.encode(uint256(0)));

        cheats.startPrank(staker);
        cheats.expectRevert(bytes("InvestmentManager._addShares: shares should not be zero!"));
        investmentManager.depositIntoStrategy(strategy, token, amount);
        cheats.stopPrank();
    }

    function test_addSharesRevertsWhenDepositWouldExeedMaxArrayLength() external {
        address staker = address(this);
        IERC20 token = dummyToken;
        uint256 amount = 1e18;
        IInvestmentStrategy strategy = dummyStrat;

        cheats.startPrank(staker);
        // uint256 MAX_INVESTOR_STRATS_LENGTH = investmentManager.MAX_INVESTOR_STRATS_LENGTH();
        uint256 MAX_INVESTOR_STRATS_LENGTH = 32;

        // loop that deploys a new strategy and deposits into it
        for (uint256 i = 0; i < MAX_INVESTOR_STRATS_LENGTH; ++i) {
            investmentManager.depositIntoStrategy(strategy, token, amount);
            dummyStrat = InvestmentStrategyBase(
                address(
                    new TransparentUpgradeableProxy(
                        address(dummyStratImplementation),
                        address(proxyAdmin),
                        abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, dummyToken, pauserRegistry)
                    )
                )
            );
            strategy = dummyStrat;
        }

        require(investmentManager.investorStratsLength(staker) == MAX_INVESTOR_STRATS_LENGTH, 
            "investmentManager.investorStratsLength(staker) != MAX_INVESTOR_STRATS_LENGTH");

        cheats.expectRevert(bytes("InvestmentManager._addShares: deposit would exceed MAX_INVESTOR_STRATS_LENGTH"));
        investmentManager.depositIntoStrategy(strategy, token, amount);

        cheats.stopPrank();
    }

    function test_depositIntoStrategyRevertsWhenTokenSafeTransferFromReverts() external {
        // replace 'dummyStrat' with one that uses a reverting token
        dummyToken = IERC20(address(new Reverter()));
        dummyStrat = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(dummyStratImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, dummyToken, pauserRegistry)
                )
            )
        );

        address staker = address(this);
        IERC20 token = dummyToken;
        uint256 amount = 1e18;
        IInvestmentStrategy strategy = dummyStrat;

        cheats.startPrank(staker);
        cheats.expectRevert();
        investmentManager.depositIntoStrategy(strategy, token, amount);
        cheats.stopPrank();
    }

    function test_depositIntoStrategyRevertsWhenTokenDoesNotExist() external {
        // replace 'dummyStrat' with one that uses a non-existent token
        dummyToken = IERC20(address(5678));
        dummyStrat = InvestmentStrategyBase(
            address(
                new TransparentUpgradeableProxy(
                    address(dummyStratImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(InvestmentStrategyBase.initialize.selector, dummyToken, pauserRegistry)
                )
            )
        );

        address staker = address(this);
        IERC20 token = dummyToken;
        uint256 amount = 1e18;
        IInvestmentStrategy strategy = dummyStrat;

        cheats.startPrank(staker);
        cheats.expectRevert();
        investmentManager.depositIntoStrategy(strategy, token, amount);
        cheats.stopPrank();
    }

    function test_depositIntoStrategyRevertsWhenStrategyDepositFunctionReverts() external {
        // replace 'dummyStrat' with one that always reverts
        dummyStrat = InvestmentStrategyBase(
            address(
                new Reverter()
            )
        );

        address staker = address(this);
        IERC20 token = dummyToken;
        uint256 amount = 1e18;
        IInvestmentStrategy strategy = dummyStrat;

        cheats.startPrank(staker);
        cheats.expectRevert();
        investmentManager.depositIntoStrategy(strategy, token, amount);
        cheats.stopPrank();
    }

    function test_depositIntoStrategyRevertsWhenStrategyDoesNotExist() external {
        // replace 'dummyStrat' with one that does not exist
        dummyStrat = InvestmentStrategyBase(
            address(5678)
        );

        address staker = address(this);
        IERC20 token = dummyToken;
        uint256 amount = 1e18;
        IInvestmentStrategy strategy = dummyStrat;

        cheats.startPrank(staker);
        cheats.expectRevert();
        investmentManager.depositIntoStrategy(strategy, token, amount);
        cheats.stopPrank();
    }

    function test_removeSharesRevertsWhenShareAmountIsZero() external {
        uint256 amount = 1e18;
        address staker = address(this);
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;

        testDepositIntoStrategySuccessfully(staker, amount);

        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        strategyArray[0] = strategy;
        tokensArray[0] = token;
        shareAmounts[0] = 0;

        // freeze the staker
        slasherMock.freezeOperator(staker);

        address slashedAddress = address(this);
        address recipient = address(333);
        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;

        cheats.startPrank(investmentManager.owner());
        cheats.expectRevert(bytes("InvestmentManager._removeShares: shareAmount should not be zero!"));
        investmentManager.slashShares(slashedAddress, recipient, strategyArray, tokensArray, strategyIndexes, shareAmounts);
        cheats.stopPrank();
    }

    function test_removeSharesRevertsWhenShareAmountIsTooLarge() external {
        uint256 amount = 1e18;
        address staker = address(this);
        IInvestmentStrategy strategy = dummyStrat;
        IERC20 token = dummyToken;

        testDepositIntoStrategySuccessfully(staker, amount);

        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        strategyArray[0] = strategy;
        tokensArray[0] = token;
        shareAmounts[0] = amount + 1;

        // freeze the staker
        slasherMock.freezeOperator(staker);

        address slashedAddress = address(this);
        address recipient = address(333);
        uint256[] memory strategyIndexes = new uint256[](1);
        strategyIndexes[0] = 0;

        cheats.startPrank(investmentManager.owner());
        cheats.expectRevert(bytes("InvestmentManager._removeShares: shareAmount too high"));
        investmentManager.slashShares(slashedAddress, recipient, strategyArray, tokensArray, strategyIndexes, shareAmounts);
        cheats.stopPrank();
    }

    // INTERNAL / HELPER FUNCTIONS
    function _beaconChainReentrancyTestsSetup() internal {
        // prepare InvestmentManager with EigenPodManager and Delegation replaced with a Reenterer contract
        reenterer = new Reenterer();
        investmentManagerImplementation = new InvestmentManager(IEigenLayerDelegation(address(reenterer)), IEigenPodManager(address(reenterer)), slasherMock);
        investmentManager = InvestmentManager(
            address(
                new TransparentUpgradeableProxy(
                    address(investmentManagerImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(InvestmentManager.initialize.selector, pauserRegistry, initialOwner)
                )
            )
        );
    }

    function _setUpQueuedWithdrawalStructSingleStrat(address staker, address withdrawer, IERC20 token, IInvestmentStrategy strategy, uint256 shareAmount)
        internal view returns (IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal, IInvestmentManager.StratsTokensShares memory sts, bytes32 withdrawalRoot)
    {
        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        strategyArray[0] = strategy;
        tokensArray[0] = token;
        shareAmounts[0] = shareAmount;
        sts = IInvestmentManager.StratsTokensShares(strategyArray, tokensArray, shareAmounts);
        IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce = IInvestmentManager.WithdrawerAndNonce({
            withdrawer: withdrawer,
            nonce: uint96(investmentManager.numWithdrawalsQueued(staker))
        });
        queuedWithdrawal = 
            IInvestmentManager.QueuedWithdrawal({
                strategies: sts.strategies,
                tokens: sts.tokens,
                shares: sts.shares,
                depositor: staker,
                withdrawerAndNonce: withdrawerAndNonce,
                withdrawalStartBlock: uint32(block.number),
                delegatedAddress: investmentManager.delegation().delegatedTo(staker)
            }
        );
        // calculate the withdrawal root
        withdrawalRoot = investmentManager.calculateWithdrawalRoot(queuedWithdrawal);
        return (queuedWithdrawal, sts, withdrawalRoot);
    }
}