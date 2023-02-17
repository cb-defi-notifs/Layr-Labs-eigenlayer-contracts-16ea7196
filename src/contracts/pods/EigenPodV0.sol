// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/AddressUpgradeable.sol";

import "../interfaces/IETHPOSDeposit.sol";
import "../interfaces/IEigenPodManager.sol";
import "../interfaces/IEigenPodV0.sol";
import "../interfaces/IEigenPodPaymentEscrow.sol";
import "../interfaces/IPausable.sol";

import "./EigenPodPausingConstants.sol";

import "forge-std/Test.sol";

/**
 * @title The implementation contract used for restaking beacon chain ETH on EigenLayer 
 * @author Layr Labs, Inc.
 * @notice The main functionalities are:
 * - creating new ETH validators with their withdrawal credentials pointed to this contract
 * - proving from beacon chain state roots that withdrawal credentials are pointed to this contract
 * - proving from beacon chain state roots the balances of ETH validators with their withdrawal credentials
 *   pointed to this contract
 * - updating aggregate balances in the EigenPodManager
 * - withdrawing eth when withdrawals are initiated
 * @dev Note that all beacon chain balances are stored as gwei within the beacon chain datastructures. We choose
 *   to account balances in terms of gwei in the EigenPod contract and convert to wei when making calls to other contracts
 */
contract EigenPodV0 is IEigenPodV0, Initializable, ReentrancyGuardUpgradeable, EigenPodPausingConstants {
    uint256 internal constant GWEI_TO_WEI = 1e9;

    /// @notice This is the beacon chain deposit contract
    IETHPOSDeposit internal immutable ethPOS;

    /// @notice Escrow contract used for payment routing, to provide an extra "safety net"
    IEigenPodPaymentEscrow immutable public eigenPodPaymentEscrow;

    /// @notice The single EigenPodManager for EigenLayer
    IEigenPodManager public eigenPodManager;

    /// @notice The owner of this EigenPod
    address public podOwner;

    /// @notice The latest block number at which the pod owner withdrew the balance of the pod
    uint64 public mostRecentWithdrawalBlockNumber;

    /// @notice Emitted when an ETH validator stakes via this eigenPod
    event EigenPodStaked(bytes pubkey);

    modifier onlyEigenPodManager {
        require(msg.sender == address(eigenPodManager), "EigenPod.onlyEigenPodManager: not eigenPodManager");
        _;
    }

    modifier onlyEigenPodOwner {
        require(msg.sender == podOwner, "EigenPod.onlyEigenPodOwner: not podOwner");
        _;
    }

    /**
     * @notice Based on 'Pausable' code, but uses the storage of the EigenPodManager instead of this contract. This construction
     * is necessary for enabling pausing all EigenPods at the same time (due to EigenPods being Beacon Proxies).
     * Modifier throws if the `indexed`th bit of `_paused` in the EigenPodManager is 1, i.e. if the `index`th pause switch is flipped.
     */
    modifier onlyWhenNotPaused(uint8 index) {
        require(!IPausable(address(eigenPodManager)).paused(index), "EigenPod.onlyWhenNotPaused: index is paused in EigenPodManager");
        _;
    }

    constructor(
        IETHPOSDeposit _ethPOS,
        IEigenPodPaymentEscrow _eigenPodPaymentEscrow
    ) {
        ethPOS = _ethPOS;
        eigenPodPaymentEscrow = _eigenPodPaymentEscrow;
        _disableInitializers();
    }

    /// @notice Used to initialize the pointers to contracts crucial to the pod's functionality, in beacon proxy construction from EigenPodManager
    function initialize(IEigenPodManager _eigenPodManager, address _podOwner) external initializer {
        require(_podOwner != address(0), "EigenPod.initialize: podOwner cannot be zero address");
        eigenPodManager = _eigenPodManager;
        podOwner = _podOwner;
    }

    /// @notice Called by EigenPodManager when the owner wants to create another ETH validator.
    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable onlyEigenPodManager {
        // stake on ethpos
        require(msg.value == 32 ether, "EigenPod.stake: must initially stake for any validator with 32 ether");
        ethPOS.deposit{value : 32 ether}(pubkey, _podWithdrawalCredentials(), signature, depositDataRoot);
        emit EigenPodStaked(pubkey);
    }

    /// @notice Called by the pod owner to withdraw the balance of the pod
    function withdraw() external onlyEigenPodOwner {
        mostRecentWithdrawalBlockNumber = uint32(block.number);
        _sendETH(podOwner, address(this).balance);
    }

    // INTERNAL FUNCTIONS

    function _podWithdrawalCredentials() internal view returns(bytes memory) {
        return abi.encodePacked(bytes1(uint8(1)), bytes11(0), address(this));
    }

    function _sendETH(address recipient, uint256 amountWei) internal {
        eigenPodPaymentEscrow.createPayment{value: amountWei}(podOwner, recipient);
    }
}