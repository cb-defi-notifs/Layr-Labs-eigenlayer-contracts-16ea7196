// //SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../contracts/pods/EigenPodPaymentEscrow.sol";
import "../../contracts/permissions/PauserRegistry.sol";

import "../mocks/EigenPodManagerMock.sol";
import "../mocks/Reenterer.sol";

import "forge-std/Test.sol";

contract EigenPodPaymentEscrowUnitTests is Test {

    Vm cheats = Vm(HEVM_ADDRESS);

    ProxyAdmin public proxyAdmin;
    PauserRegistry public pauserRegistry;

    EigenPodManagerMock public eigenPodManagerMock;

    EigenPodPaymentEscrow public eigenPodPaymentEscrowImplementation;
    EigenPodPaymentEscrow public eigenPodPaymentEscrow;

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

        eigenPodPaymentEscrowImplementation = new EigenPodPaymentEscrow(eigenPodManagerMock);

        uint256 initPausedStatus = 0;
        uint256 withdrawalDelayBlocks = eigenPodPaymentEscrowImplementation.MAX_WITHDRAWAL_DELAY_BLOCKS();
        eigenPodPaymentEscrow = EigenPodPaymentEscrow(
            address(
                new TransparentUpgradeableProxy(
                    address(eigenPodPaymentEscrowImplementation),
                    address(proxyAdmin),
                    abi.encodeWithSelector(EigenPodPaymentEscrow.initialize.selector, initialOwner, pauserRegistry, initPausedStatus, withdrawalDelayBlocks)
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
        uint256 withdrawalDelayBlocks = eigenPodPaymentEscrow.MAX_WITHDRAWAL_DELAY_BLOCKS();
        cheats.expectRevert(bytes("Initializable: contract is already initialized"));
        eigenPodPaymentEscrow.initialize(initialOwner, pauserRegistry, initPausedStatus, withdrawalDelayBlocks);
    }

    function testCreatePaymentNonzeroAmount(uint224 paymentAmount, address podOwner, address recipient) public filterFuzzedAddressInputs(podOwner) {
        cheats.assume(paymentAmount != 0);

        IEigenPodPaymentEscrow.UserPayments memory userPaymentsBefore = eigenPodPaymentEscrow.userPayments(recipient);

        address podAddress = address(eigenPodManagerMock.getPod(podOwner));
        cheats.deal(podAddress, paymentAmount);
        cheats.startPrank(podAddress);
        eigenPodPaymentEscrow.createPayment{value: paymentAmount}(podOwner, recipient);
        cheats.stopPrank();

        IEigenPodPaymentEscrow.UserPayments memory userPaymentsAfter = eigenPodPaymentEscrow.userPayments(recipient);

        require(userPaymentsAfter.payments.length == userPaymentsBefore.payments.length + 1,
            "userPaymentsAfter.payments.length != userPaymentsBefore.payments.length + 1");

        IEigenPodPaymentEscrow.Payment memory payment = userPaymentsAfter.payments[userPaymentsAfter.payments.length - 1];
        require(payment.amount == paymentAmount, "payment.amount != paymentAmount");
        require(payment.blockCreated == block.number, "payment.blockCreated != block.number");
    }

    function testCreatePaymentZeroAmount(address podOwner, address recipient) public filterFuzzedAddressInputs(podOwner) {
        IEigenPodPaymentEscrow.UserPayments memory userPaymentsBefore = eigenPodPaymentEscrow.userPayments(recipient);
        uint224 paymentAmount = 0;

        address podAddress = address(eigenPodManagerMock.getPod(podOwner));
        cheats.deal(podAddress, paymentAmount);
        cheats.startPrank(podAddress);
        eigenPodPaymentEscrow.createPayment{value: paymentAmount}(podOwner, recipient);
        cheats.stopPrank();

        IEigenPodPaymentEscrow.UserPayments memory userPaymentsAfter = eigenPodPaymentEscrow.userPayments(recipient);

        // verify that no new 'payment' was created
        require(userPaymentsAfter.payments.length == userPaymentsBefore.payments.length,
            "userPaymentsAfter.payments.length != userPaymentsBefore.payments.length");
    }

    function testClaimPayments(uint8 paymentsToCreate, uint8 maxNumberOfPaymentsToClaim, uint256 pseudorandomNumber_, address recipient, bool useOverloadedFunction)
        public filterFuzzedAddressInputs(recipient)
    {
        // filter contracts out of fuzzed recipient input, since most don't implement a payable fallback function
        cheats.assume(!Address.isContract(recipient));
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

        IEigenPodPaymentEscrow.UserPayments memory userPaymentsBefore = eigenPodPaymentEscrow.userPayments(recipient);
        uint256 userBalanceBefore = recipient.balance;

        // pre-condition check
        require(userPaymentsBefore.payments.length == paymentsCreated, "userPaymentsBefore.payments.length != paymentsCreated");

        // roll forward the block number enough to make the payments claimable
        cheats.roll(block.number + eigenPodPaymentEscrow.withdrawalDelayBlocks());

        // claim the payments
        if (paymentsCreated != 0) {
            if (useOverloadedFunction) {
                eigenPodPaymentEscrow.claimPayments(recipient, maxNumberOfPaymentsToClaim);                
            } else {
                cheats.startPrank(recipient);
                eigenPodPaymentEscrow.claimPayments(maxNumberOfPaymentsToClaim);
                cheats.stopPrank();
            }
        }

        IEigenPodPaymentEscrow.UserPayments memory userPaymentsAfter = eigenPodPaymentEscrow.userPayments(recipient);
        uint256 userBalanceAfter = recipient.balance;

        // post-conditions
        uint256 numberOfPaymentsThatShouldBeCompleted = (maxNumberOfPaymentsToClaim > paymentsCreated) ? paymentsCreated : maxNumberOfPaymentsToClaim;
        require(userPaymentsAfter.paymentsCompleted == userPaymentsBefore.paymentsCompleted + numberOfPaymentsThatShouldBeCompleted,
            "userPaymentsAfter.paymentsCompleted != userPaymentsBefore.paymentsCompleted + numberOfPaymentsThatShouldBeCompleted");
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
        cheats.roll(block.number + eigenPodPaymentEscrow.withdrawalDelayBlocks() / 2);

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
        cheats.roll(block.number + eigenPodPaymentEscrow.withdrawalDelayBlocks() / 2);

        IEigenPodPaymentEscrow.UserPayments memory userPaymentsBefore = eigenPodPaymentEscrow.userPayments(recipient);
        uint256 userBalanceBefore = recipient.balance;

        // pre-condition check
        require(userPaymentsBefore.payments.length == paymentsCreated_1 + paymentsCreated_2,
            "userPaymentsBefore.payments.length != paymentsCreated_1 + paymentsCreated_2");

        // claim the payments
        if (paymentsCreated_1 + paymentsCreated_2 != 0) {
            if (useOverloadedFunction) {
                eigenPodPaymentEscrow.claimPayments(recipient, maxNumberOfPaymentsToClaim);                
            } else {
                cheats.startPrank(recipient);
                eigenPodPaymentEscrow.claimPayments(maxNumberOfPaymentsToClaim);
                cheats.stopPrank();
            }
        }

        IEigenPodPaymentEscrow.UserPayments memory userPaymentsAfter = eigenPodPaymentEscrow.userPayments(recipient);
        uint256 userBalanceAfter = recipient.balance;

        // post-conditions
        uint256 numberOfPaymentsThatShouldBeCompleted = (maxNumberOfPaymentsToClaim > paymentsCreated_1) ? paymentsCreated_1 : maxNumberOfPaymentsToClaim;
        require(userPaymentsAfter.paymentsCompleted == userPaymentsBefore.paymentsCompleted + numberOfPaymentsThatShouldBeCompleted,
            "userPaymentsAfter.paymentsCompleted != userPaymentsBefore.paymentsCompleted + numberOfPaymentsThatShouldBeCompleted");
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
        cheats.roll(block.number + eigenPodPaymentEscrow.withdrawalDelayBlocks());

        // prepare the Reenterer contract
        address targetToUse = address(eigenPodPaymentEscrow);
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
            eigenPodPaymentEscrow.claimPayments(recipient, maxNumberOfPaymentsToClaim);                
        } else {
            cheats.startPrank(recipient);
            eigenPodPaymentEscrow.claimPayments(maxNumberOfPaymentsToClaim);
            cheats.stopPrank();
        }
    }

    function testClaimPayments_RevertsWhenPaused(bool useOverloadedFunction) external {
        uint8 maxNumberOfPaymentsToClaim = 1;
        address recipient = address(22222);

        // pause payment claims
        cheats.startPrank(eigenPodPaymentEscrow.pauserRegistry().pauser());
        eigenPodPaymentEscrow.pause(2 ** PAUSED_PAYMENT_CLAIMS);
        cheats.stopPrank();

        cheats.expectRevert(bytes("Pausable: index is paused"));
        if (useOverloadedFunction) {
            eigenPodPaymentEscrow.claimPayments(recipient, maxNumberOfPaymentsToClaim);                
        } else {
            cheats.startPrank(recipient);
            eigenPodPaymentEscrow.claimPayments(maxNumberOfPaymentsToClaim);
            cheats.stopPrank();
        }
    }

    function testSetWithdrawalDelayBlocks(uint16 valueToSet) external {
        // filter fuzzed inputs to allowed amounts
        cheats.assume(valueToSet <= eigenPodPaymentEscrow.MAX_WITHDRAWAL_DELAY_BLOCKS());

        // set the `withdrawalDelayBlocks` variable
        cheats.startPrank(eigenPodPaymentEscrow.owner());
        eigenPodPaymentEscrow.setWithdrawalDelayBlocks(valueToSet);
        cheats.stopPrank();
        require(eigenPodPaymentEscrow.withdrawalDelayBlocks() == valueToSet, "eigenPodPaymentEscrow.withdrawalDelayBlocks() != valueToSet");
    }

    function testSetWithdrawalDelayBlocksRevertsWhenCalledByNotOwner(address notOwner) filterFuzzedAddressInputs(notOwner) external {
        cheats.assume(notOwner != eigenPodPaymentEscrow.owner());

        uint256 valueToSet = 1;
        // set the `withdrawalDelayBlocks` variable
        cheats.startPrank(notOwner);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        eigenPodPaymentEscrow.setWithdrawalDelayBlocks(valueToSet);
        cheats.stopPrank();
    }

    function testSetWithdrawalDelayBlocksRevertsWhenInputValueTooHigh(uint256 valueToSet) external {
        // filter fuzzed inputs to disallowed amounts
        cheats.assume(valueToSet > eigenPodPaymentEscrow.MAX_WITHDRAWAL_DELAY_BLOCKS());

        // attempt to set the `withdrawalDelayBlocks` variable
        cheats.startPrank(eigenPodPaymentEscrow.owner());
        cheats.expectRevert(bytes("EigenPodPaymentEscrow._setWithdrawalDelayBlocks: newValue too large"));
        eigenPodPaymentEscrow.setWithdrawalDelayBlocks(valueToSet);
    }

    function _getPseudorandomNumber() internal returns (uint256) {
        _pseudorandomNumber = uint256(keccak256(abi.encode(_pseudorandomNumber)));
        return _pseudorandomNumber;
    }
}