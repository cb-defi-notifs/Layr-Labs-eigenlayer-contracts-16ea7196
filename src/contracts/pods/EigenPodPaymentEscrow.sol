// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
// import "@openzeppelin-upgrades/contracts/utils/AddressUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";
import "../interfaces/IEigenPodPaymentEscrow.sol";
import "../permissions/Pausable.sol";

contract EigenPodPaymentEscrow is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, Pausable, IEigenPodPaymentEscrow {
    struct Payment {
        uint256 amount;
        uint256 blockCreated;
    }

    struct UserPayments {
        uint256 paymentsCompleted;
        Payment[] payments;
    }

    uint256 public withdrawalDelayBlocks;

    mapping(address => UserPayments) internal _userPayments;

    function createPayment(address recipient) external payable {
        uint256 paymentAmount = msg.value;
        Payment memory payment = Payment({
            amount: paymentAmount,
            blockCreated: block.number
        });
        _userPayments[recipient].payments.push(payment);
    }

    function userPayments(address user) external view returns (UserPayments memory) {
        return _userPayments[user];
    }
}