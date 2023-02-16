// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import "../interfaces/IEigenPodManagerV0.sol";
import "../interfaces/IETHPOSDeposit.sol";
import "../interfaces/IEigenPodV0.sol";

import "../permissions/Pausable.sol";
import "./EigenPodPausingConstants.sol";

/**
 * @title The contract used for creating and managing EigenPods
 * @author Layr Labs, Inc.
 * @notice The main functionalities are:
 * - creating EigenPods
 * - staking for new validators on EigenPods
 * - keeping track of the balances of all validators of EigenPods, and their stake in EigenLayer
 * - withdrawing eth when withdrawals are initiated
 */
contract EigenPodManagerV0 is Initializable, OwnableUpgradeable, Pausable, IEigenPodManagerV0, EigenPodPausingConstants {
    /// @notice The ETH2 Deposit Contract
    IETHPOSDeposit public immutable ethPOS;
    
    /// @notice Beacon proxy to which the EigenPods point
    IBeacon public immutable eigenPodBeacon;
    
    /// @notice Pod owner to deployed EigenPod address
    mapping(address => IEigenPodV0) internal _podByOwner;

    /// @notice Emitted to notify the deployment of an EigenPod
    event PodDeployed(address indexed eigenPod, address indexed podOwner);

    modifier onlyEigenPod(address podOwner) {
        require(address(getPod(podOwner)) == msg.sender, "EigenPodManager.onlyEigenPod: not a pod");
        _;
    }

    constructor(IETHPOSDeposit _ethPOS, IBeacon _eigenPodBeacon) {
        ethPOS = _ethPOS;
        eigenPodBeacon = _eigenPodBeacon;
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        IPauserRegistry _pauserRegistry,
        uint256 _initPausedStatus
    ) public initializer {
        _transferOwnership(initialOwner);
        _initializePauser(_pauserRegistry, _initPausedStatus);
    }

    /**
     * @notice Creates an EigenPod for the sender.
     * @dev Function will revert if the `msg.sender` already has an EigenPod.
     */
    function createPod() external {
        require(!hasPod(msg.sender), "EigenPodManager.createPod: Sender already has a pod");
        // deploy a pod if the sender doesn't have one already
        _deployPod();
    }

    /**
     * @notice Stakes for a new beacon chain validator on the sender's EigenPod. 
     * Also creates an EigenPod for the sender if they don't have one already.
     * @param pubkey The 48 bytes public key of the beacon chain validator.
     * @param signature The validator's signature of the deposit data.
     * @param depositDataRoot The root/hash of the deposit data for the validator's deposit.
     */
    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable {
        IEigenPodV0 pod = getPod(msg.sender);
        if(!hasPod(msg.sender)) {
            //deploy a pod if the sender doesn't have one already
            pod = _deployPod();
        }
        pod.stake{value: msg.value}(pubkey, signature, depositDataRoot);
    }

    // INTERNAL FUNCTIONS
    function _deployPod() internal onlyWhenNotPaused(PAUSED_NEW_EIGENPODS) returns (IEigenPodV0) {
        IEigenPodV0 pod = 
            IEigenPodV0(
                Create2.deploy(
                    0, 
                    bytes32(uint256(uint160(msg.sender))), 
                    // set the beacon address to the eigenPodBeacon and initialize it
                    abi.encodePacked(
                        type(BeaconProxy).creationCode, 
                        abi.encode(eigenPodBeacon, abi.encodeWithSelector(IEigenPodV0.initialize.selector, IEigenPodManagerV0(address(this)), msg.sender))
                    )
                )
            );
        emit PodDeployed(address(pod), msg.sender);
        return pod;
    }

    // VIEW FUNCTIONS
    /// @notice Returns the address of the `podOwner`'s EigenPod (whether it is deployed yet or not).
    function getPod(address podOwner) public view returns (IEigenPodV0) {
        IEigenPodV0 pod = _podByOwner[podOwner];
        // if pod does not exist already, calculate what its address *will be* once it is deployed
        if (address(pod) == address(0)) {
            pod = IEigenPodV0(
                Create2.computeAddress(
                    bytes32(uint256(uint160(podOwner))), //salt
                    keccak256(abi.encodePacked(
                        type(BeaconProxy).creationCode, 
                        abi.encode(eigenPodBeacon, abi.encodeWithSelector(IEigenPodV0.initialize.selector, IEigenPodManagerV0(address(this)), podOwner))
                    )) //bytecode
                ));
        }
        return pod;
    }

    /// @notice Returns 'true' if the `podOwner` has created an EigenPod, and 'false' otherwise.
    function hasPod(address podOwner) public view returns (bool) {
        return address(_podByOwner[podOwner]) != address(0);
    }
}