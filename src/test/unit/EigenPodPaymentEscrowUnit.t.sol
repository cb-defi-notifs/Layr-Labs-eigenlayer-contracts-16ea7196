// //SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../contracts/pods/EigenPodPaymentEscrow.sol";
import "../../contracts/permissions/PauserRegistry.sol";

import "../mocks/EigenPodManagerMock.sol";

import "forge-std/Test.sol";

contract EigenPodPaymentEscrowUnitTests is Test {

    Vm cheats = Vm(HEVM_ADDRESS);

    ProxyAdmin public proxyAdmin;
    PauserRegistry public pauserRegistry;

    EigenPodManagerMock public eigenPodManagerMock;

    EigenPodPaymentEscrow public eigenPodPaymentEscrowImplementation;
    EigenPodPaymentEscrow public eigenPodPaymentEscrow;

    address public pauser = address(555);
    address public unpauser = address(999);

    address initialOwner = address(this);

    uint256 internal _pseudorandomNumber;

    uint224[] public paymentAmounts;

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

        // excude the zero address and the proxyAdmin from fuzzed inputs
        addressIsExcludedFromFuzzedInputs[address(0)] = true;
        addressIsExcludedFromFuzzedInputs[address(proxyAdmin)] = true;
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

    function testClaimPayments(uint8 paymentsToCreate, uint8 maxNumberOfPaymentsToClaim, uint256 pseudorandomNumber_) public {
        address podOwner = address(22222);
        address recipient = address(11111);

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
            eigenPodPaymentEscrow.claimPayments(recipient, maxNumberOfPaymentsToClaim);
        }

        IEigenPodPaymentEscrow.UserPayments memory userPaymentsAfter = eigenPodPaymentEscrow.userPayments(recipient);
        uint256 userBalanceAfter = recipient.balance;

        // post-conditions
        uint8 numberOfPaymentsThatShouldBeCompleted = (maxNumberOfPaymentsToClaim > paymentsCreated) ? paymentsCreated : maxNumberOfPaymentsToClaim;
        require(userPaymentsAfter.paymentsCompleted == userPaymentsBefore.paymentsCompleted + numberOfPaymentsThatShouldBeCompleted,
            "userPaymentsAfter.paymentsCompleted != userPaymentsBefore.paymentsCompleted + numberOfPaymentsThatShouldBeCompleted");
        uint256 totalPaymentAmount = 0;
        for (uint256 i = 0; i < numberOfPaymentsThatShouldBeCompleted; ++i) {
            totalPaymentAmount += paymentAmounts[i];
        }
        require(userBalanceAfter == userBalanceBefore + totalPaymentAmount,
            "userBalanceAfter != userBalanceBefore + totalPaymentAmount");
    }

    function _getPseudorandomNumber() internal returns (uint256) {
        _pseudorandomNumber = uint256(keccak256(abi.encode(_pseudorandomNumber)));
        return _pseudorandomNumber;
    }
}