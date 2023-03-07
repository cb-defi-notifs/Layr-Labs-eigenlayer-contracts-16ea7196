// //SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../contracts/pods/DelayedWithdrawalRouter.sol";
import "../../contracts/permissions/PauserRegistry.sol";

import "../mocks/EigenPodManagerMock.sol";
import "../mocks/Reenterer.sol";

import "forge-std/Test.sol";

contract DelayedWithdrawalRouterUnitTests is Test {

    Vm cheats = Vm(HEVM_ADDRESS);

    ProxyAdmin public proxyAdmin;
    PauserRegistry public pauserRegistry;

    EigenPodManagerMock public eigenPodManagerMock;

    DelayedWithdrawalRouter public delayedWithdrawalRouterImplementation;
    DelayedWithdrawalRouter public delayedWithdrawalRouter;

    Reenterer public reenterer;

    address public pauser = address(555);
    address public unpauser = address(999);

    address initialOwner = address(this);

    uint224[] public paymentAmounts;

    uint256 internal _pseudorandomNumber;

    // index for flag that pauses withdrawals (i.e. 'payment claims') when set
    uint8 internal constant PAUSED_PAYMENT_CLAIMS = 0;

    mapping(address => bool) public addressIsExcludedFromFuzzedInputs;

    modifier filterFuzzedAddressInputs(address fuzzedAddress) {
        cheats.assume(!addressIsExcludedFromFuzzedInputs[fuzzedAddress]);
        _;
    }

    function setUp() external {
        proxyAdmin = new ProxyAdmin();

        pauserRegistry = new PauserRegistry(pauser, unpauser);

        eigenPodManagerMock = new EigenPodManagerMock();

        delayedWithdrawalRouterImplementation = new DelayedWithdrawalRouter(eigenPodManagerMock);

        uint256 initPausedStatus = 0;
        uint256 withdrawalDelayBlocks = delayedWithdrawalRouterImplementation.MAX_WITHDRAWAL_DELAY_BLOCKS();
        delayedWithdrawalRouter = DelayedWithdrawalRouter(
            address(
                new TransparentUpgradeableProxy(
                    address(delayedWithdrawalRouterImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(DelayedWithdrawalRouter.initialize.selector, initialOwner, pauserRegistry, initPausedStatus, withdrawalDelayBlocks)
                )
            )
        );

        reenterer = new Reenterer();

        // exclude the zero address, the proxyAdmin, and this contract from fuzzed inputs
        addressIsExcludedFromFuzzedInputs[address(0)] = true;
        addressIsExcludedFromFuzzedInputs[address(proxyAdmin)] = true;
        addressIsExcludedFromFuzzedInputs[address(this)] = true;
    }

    function testCannotReinitialize() external {
        uint256 initPausedStatus = 0;
        uint256 withdrawalDelayBlocks = delayedWithdrawalRouter.MAX_WITHDRAWAL_DELAY_BLOCKS();
        cheats.expectRevert(bytes("Initializable: contract is already initialized"));
        delayedWithdrawalRouter.initialize(initialOwner, pauserRegistry, initPausedStatus, withdrawalDelayBlocks);
    }

    function testCreatePaymentNonzeroAmount(uint224 paymentAmount, address podOwner, address recipient) public filterFuzzedAddressInputs(podOwner) {
        cheats.assume(paymentAmount != 0);

        IDelayedWithdrawalRouter.UserPayments memory userWithdrawalsBefore = delayedWithdrawalRouter.userWithdrawals(recipient);

        address podAddress = address(eigenPodManagerMock.getPod(podOwner));
        cheats.deal(podAddress, paymentAmount);
        cheats.startPrank(podAddress);
        delayedWithdrawalRouter.createPayment{value: paymentAmount}(podOwner, recipient);
        cheats.stopPrank();

        IDelayedWithdrawalRouter.UserPayments memory userWithdrawalsAfter = delayedWithdrawalRouter.userWithdrawals(recipient);

        require(userWithdrawalsAfter.payments.length == userWithdrawalsBefore.payments.length + 1,
            "userWithdrawalsAfter.payments.length != userWithdrawalsBefore.payments.length + 1");

        IDelayedWithdrawalRouter.Payment memory payment = userWithdrawalsAfter.payments[userWithdrawalsAfter.payments.length - 1];
        require(payment.amount == paymentAmount, "payment.amount != paymentAmount");
        require(payment.blockCreated == block.number, "payment.blockCreated != block.number");
    }

    function testCreatePaymentZeroAmount(address podOwner, address recipient) public filterFuzzedAddressInputs(podOwner) {
        IDelayedWithdrawalRouter.UserPayments memory userWithdrawalsBefore = delayedWithdrawalRouter.userWithdrawals(recipient);
        uint224 paymentAmount = 0;

        address podAddress = address(eigenPodManagerMock.getPod(podOwner));
        cheats.deal(podAddress, paymentAmount);
        cheats.startPrank(podAddress);
        delayedWithdrawalRouter.createPayment{value: paymentAmount}(podOwner, recipient);
        cheats.stopPrank();

        IDelayedWithdrawalRouter.UserPayments memory userWithdrawalsAfter = delayedWithdrawalRouter.userWithdrawals(recipient);

        // verify that no new 'payment' was created
        require(userWithdrawalsAfter.payments.length == userWithdrawalsBefore.payments.length,
            "userWithdrawalsAfter.payments.length != userWithdrawalsBefore.payments.length");
    }

    function testClaimPayments(uint8 paymentsToCreate, uint8 maxNumberOfPaymentsToClaim, uint256 pseudorandomNumber_, address recipient, bool useOverloadedFunction)
        public filterFuzzedAddressInputs(recipient)
    {
        // filter contracts out of fuzzed recipient input, since most don't implement a payable fallback function
        cheats.assume(!Address.isContract(recipient));
        // filter out precompile addresses (they won't accept payment either)
        cheats.assume(uint160(recipient) > 256);
        // filter fuzzed inputs to avoid running out of gas & excessive test run-time
        cheats.assume(paymentsToCreate <= 32);

        address podOwner = address(88888);

        // create the payments
        _pseudorandomNumber = pseudorandomNumber_;
        uint8 paymentsCreated;
        for (uint256 i = 0; i < paymentsToCreate; ++i) {
            uint224 paymentAmount = uint224(_getPseudorandomNumber());
            if (paymentAmount != 0) {
                testCreatePaymentNonzeroAmount(paymentAmount, podOwner, recipient);
                paymentAmounts.push(paymentAmount);
                paymentsCreated += 1;
            }
        }

        IDelayedWithdrawalRouter.UserPayments memory userWithdrawalsBefore = delayedWithdrawalRouter.userWithdrawals(recipient);
        uint256 userBalanceBefore = recipient.balance;

        // pre-condition check
        require(userWithdrawalsBefore.payments.length == paymentsCreated, "userWithdrawalsBefore.payments.length != paymentsCreated");

        // roll forward the block number enough to make the payments claimable
        cheats.roll(block.number + delayedWithdrawalRouter.withdrawalDelayBlocks());

        // claim the payments
        if (paymentsCreated != 0) {
            if (useOverloadedFunction) {
                delayedWithdrawalRouter.claimPayments(recipient, maxNumberOfPaymentsToClaim);                
            } else {
                cheats.startPrank(recipient);
                delayedWithdrawalRouter.claimPayments(maxNumberOfPaymentsToClaim);
                cheats.stopPrank();
            }
        }

        IDelayedWithdrawalRouter.UserPayments memory userWithdrawalsAfter = delayedWithdrawalRouter.userWithdrawals(recipient);
        uint256 userBalanceAfter = recipient.balance;

        // post-conditions
        uint256 numberOfPaymentsThatShouldBeCompleted = (maxNumberOfPaymentsToClaim > paymentsCreated) ? paymentsCreated : maxNumberOfPaymentsToClaim;
        require(userWithdrawalsAfter.paymentsCompleted == userWithdrawalsBefore.paymentsCompleted + numberOfPaymentsThatShouldBeCompleted,
            "userWithdrawalsAfter.paymentsCompleted != userWithdrawalsBefore.paymentsCompleted + numberOfPaymentsThatShouldBeCompleted");
        uint256 totalPaymentAmount = 0;
        for (uint256 i = 0; i < numberOfPaymentsThatShouldBeCompleted; ++i) {
            totalPaymentAmount += paymentAmounts[i];
        }
        require(userBalanceAfter == userBalanceBefore + totalPaymentAmount,
            "userBalanceAfter != userBalanceBefore + totalPaymentAmount");
    }

    /**
     * @notice Creates a set of payments of length (2 * `paymentsToCreate`) where only the first half is claimable, claims using `maxNumberOfPaymentsToClaim` input,
     * and checks that only appropriate payments were claimed.
     */
    function testClaimPaymentsSomeUnclaimable(uint8 paymentsToCreate, uint8 maxNumberOfPaymentsToClaim, bool useOverloadedFunction) external {
        // filter fuzzed inputs to avoid running out of gas & excessive test run-time
        cheats.assume(paymentsToCreate <= 32);

        address podOwner = address(88888);
        address recipient = address(22222);

        // create the first set of payments
        _pseudorandomNumber = 1554;
        uint256 paymentsCreated_1;
        for (uint256 i = 0; i < paymentsToCreate; ++i) {
            uint224 paymentAmount = uint224(_getPseudorandomNumber());
            if (paymentAmount != 0) {
                testCreatePaymentNonzeroAmount(paymentAmount, podOwner, recipient);
                paymentAmounts.push(paymentAmount);
                paymentsCreated_1 += 1;
            }
        }

        // roll forward the block number half of the delay window
        cheats.roll(block.number + delayedWithdrawalRouter.withdrawalDelayBlocks() / 2);

        // create the second set of payments
        uint256 paymentsCreated_2;
        for (uint256 i = 0; i < paymentsToCreate; ++i) {
            uint224 paymentAmount = uint224(_getPseudorandomNumber());
            if (paymentAmount != 0) {
                testCreatePaymentNonzeroAmount(paymentAmount, podOwner, recipient);
                paymentAmounts.push(paymentAmount);
                paymentsCreated_2 += 1;
            }
        }

        // roll forward the block number half of the delay window -- the first set of payments should now be claimable, while the second shouldn't be!
        cheats.roll(block.number + delayedWithdrawalRouter.withdrawalDelayBlocks() / 2);

        IDelayedWithdrawalRouter.UserPayments memory userWithdrawalsBefore = delayedWithdrawalRouter.userWithdrawals(recipient);
        uint256 userBalanceBefore = recipient.balance;

        // pre-condition check
        require(userWithdrawalsBefore.payments.length == paymentsCreated_1 + paymentsCreated_2,
            "userWithdrawalsBefore.payments.length != paymentsCreated_1 + paymentsCreated_2");

        // claim the payments
        if (paymentsCreated_1 + paymentsCreated_2 != 0) {
            if (useOverloadedFunction) {
                delayedWithdrawalRouter.claimPayments(recipient, maxNumberOfPaymentsToClaim);                
            } else {
                cheats.startPrank(recipient);
                delayedWithdrawalRouter.claimPayments(maxNumberOfPaymentsToClaim);
                cheats.stopPrank();
            }
        }

        IDelayedWithdrawalRouter.UserPayments memory userWithdrawalsAfter = delayedWithdrawalRouter.userWithdrawals(recipient);
        uint256 userBalanceAfter = recipient.balance;

        // post-conditions
        uint256 numberOfPaymentsThatShouldBeCompleted = (maxNumberOfPaymentsToClaim > paymentsCreated_1) ? paymentsCreated_1 : maxNumberOfPaymentsToClaim;
        require(userWithdrawalsAfter.paymentsCompleted == userWithdrawalsBefore.paymentsCompleted + numberOfPaymentsThatShouldBeCompleted,
            "userWithdrawalsAfter.paymentsCompleted != userWithdrawalsBefore.paymentsCompleted + numberOfPaymentsThatShouldBeCompleted");
        uint256 totalPaymentAmount = 0;
        for (uint256 i = 0; i < numberOfPaymentsThatShouldBeCompleted; ++i) {
            totalPaymentAmount += paymentAmounts[i];
        }
        require(userBalanceAfter == userBalanceBefore + totalPaymentAmount,
            "userBalanceAfter != userBalanceBefore + totalPaymentAmount");
    }

    function testClaimPayments_NoneToClaim_AttemptToClaimZero(uint256 pseudorandomNumber_, bool useOverloadedFunction) external {
        uint8 paymentsToCreate = 0;
        uint8 maxNumberOfPaymentsToClaim = 0;
        address recipient = address(22222);
        testClaimPayments(paymentsToCreate, maxNumberOfPaymentsToClaim, pseudorandomNumber_, recipient, useOverloadedFunction);
    }

    function testClaimPayments_NoneToClaim_AttemptToClaimNonzero(uint256 pseudorandomNumber_, bool useOverloadedFunction) external {
        uint8 paymentsToCreate = 0;
        uint8 maxNumberOfPaymentsToClaim = 2;
        address recipient = address(22222);
        testClaimPayments(paymentsToCreate, maxNumberOfPaymentsToClaim, pseudorandomNumber_, recipient, useOverloadedFunction);
    }

    function testClaimPayments_NonzeroToClaim_AttemptToClaimZero(uint256 pseudorandomNumber_, bool useOverloadedFunction) external {
        uint8 paymentsToCreate = 2;
        uint8 maxNumberOfPaymentsToClaim = 0;
        address recipient = address(22222);
        testClaimPayments(paymentsToCreate, maxNumberOfPaymentsToClaim, pseudorandomNumber_, recipient, useOverloadedFunction);
    }

    function testClaimPayments_NonzeroToClaim_AttemptToClaimNonzero(uint8 maxNumberOfPaymentsToClaim, uint256 pseudorandomNumber_, bool useOverloadedFunction) external {
        uint8 paymentsToCreate = 2;
        address recipient = address(22222);
        testClaimPayments(paymentsToCreate, maxNumberOfPaymentsToClaim, pseudorandomNumber_, recipient, useOverloadedFunction);
    }

    function testClaimPayments_RevertsOnAttemptingReentrancy(bool useOverloadedFunction) external {
        uint8 maxNumberOfPaymentsToClaim = 1;
        address recipient = address(reenterer);
        address podOwner = address(reenterer);

        // create the payment
        uint224 paymentAmount = 123;
        testCreatePaymentNonzeroAmount(paymentAmount, podOwner, recipient);

        // roll forward the block number enough to make the payment claimable
        cheats.roll(block.number + delayedWithdrawalRouter.withdrawalDelayBlocks());

        // prepare the Reenterer contract
        address targetToUse = address(delayedWithdrawalRouter);
        uint256 msgValueToUse = 0;
        bytes memory expectedRevertDataToUse = bytes("ReentrancyGuard: reentrant call");
        bytes memory callDataToUse;
        if (useOverloadedFunction) {
            callDataToUse = abi.encodeWithSignature(
                "claimPayments(address,uint256)", address(22222), maxNumberOfPaymentsToClaim);
        } else {
            callDataToUse  = abi.encodeWithSignature(
                "claimPayments(uint256)", maxNumberOfPaymentsToClaim);
        }
        reenterer.prepare(targetToUse, msgValueToUse, callDataToUse, expectedRevertDataToUse);

        if (useOverloadedFunction) {
            delayedWithdrawalRouter.claimPayments(recipient, maxNumberOfPaymentsToClaim);                
        } else {
            cheats.startPrank(recipient);
            delayedWithdrawalRouter.claimPayments(maxNumberOfPaymentsToClaim);
            cheats.stopPrank();
        }
    }

    function testClaimPayments_RevertsWhenPaused(bool useOverloadedFunction) external {
        uint8 maxNumberOfPaymentsToClaim = 1;
        address recipient = address(22222);

        // pause payment claims
        cheats.startPrank(delayedWithdrawalRouter.pauserRegistry().pauser());
        delayedWithdrawalRouter.pause(2 ** PAUSED_PAYMENT_CLAIMS);
        cheats.stopPrank();

        cheats.expectRevert(bytes("Pausable: index is paused"));
        if (useOverloadedFunction) {
            delayedWithdrawalRouter.claimPayments(recipient, maxNumberOfPaymentsToClaim);                
        } else {
            cheats.startPrank(recipient);
            delayedWithdrawalRouter.claimPayments(maxNumberOfPaymentsToClaim);
            cheats.stopPrank();
        }
    }

    function testSetWithdrawalDelayBlocks(uint16 valueToSet) external {
        // filter fuzzed inputs to allowed amounts
        cheats.assume(valueToSet <= delayedWithdrawalRouter.MAX_WITHDRAWAL_DELAY_BLOCKS());

        // set the `withdrawalDelayBlocks` variable
        cheats.startPrank(delayedWithdrawalRouter.owner());
        delayedWithdrawalRouter.setWithdrawalDelayBlocks(valueToSet);
        cheats.stopPrank();
        require(delayedWithdrawalRouter.withdrawalDelayBlocks() == valueToSet, "delayedWithdrawalRouter.withdrawalDelayBlocks() != valueToSet");
    }

    function testSetWithdrawalDelayBlocksRevertsWhenCalledByNotOwner(address notOwner) filterFuzzedAddressInputs(notOwner) external {
        cheats.assume(notOwner != delayedWithdrawalRouter.owner());

        uint256 valueToSet = 1;
        // set the `withdrawalDelayBlocks` variable
        cheats.startPrank(notOwner);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        delayedWithdrawalRouter.setWithdrawalDelayBlocks(valueToSet);
        cheats.stopPrank();
    }

    function testSetWithdrawalDelayBlocksRevertsWhenInputValueTooHigh(uint256 valueToSet) external {
        // filter fuzzed inputs to disallowed amounts
        cheats.assume(valueToSet > delayedWithdrawalRouter.MAX_WITHDRAWAL_DELAY_BLOCKS());

        // attempt to set the `withdrawalDelayBlocks` variable
        cheats.startPrank(delayedWithdrawalRouter.owner());
        cheats.expectRevert(bytes("DelayedWithdrawalRouter._setWithdrawalDelayBlocks: newValue too large"));
        delayedWithdrawalRouter.setWithdrawalDelayBlocks(valueToSet);
    }

    function _getPseudorandomNumber() internal returns (uint256) {
        _pseudorandomNumber = uint256(keccak256(abi.encode(_pseudorandomNumber)));
        return _pseudorandomNumber;
    }
}