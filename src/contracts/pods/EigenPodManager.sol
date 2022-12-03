// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IEigenPodManager.sol";
import "../interfaces/IETHPOSDeposit.sol";
import "../interfaces/IEigenPod.sol";
import "../interfaces/IBeaconChainOracle.sol";

/**
 * @title The contract used for creating and managing EigenPods
 * @author Layr Labs, Inc.
 * @notice The main functionalities are:
 * - creating EigenPods
 * - staking for new validators on EigenPods
 * - keeping track of the balances of all validators of EigenPods, and their stake in EigenLayer
 * - withdrawing eth when withdrawals are initiated
 */
contract EigenPodManager is Initializable, OwnableUpgradeable, IEigenPodManager {
    //TODO: change this to constant in prod
    IETHPOSDeposit immutable ethPOS;
    
    /// @notice Beacon proxy to which the EigenPods point
    IBeacon public immutable eigenPodBeacon;

    /// @notice EigenLayer's InvestmentManager contract
    IInvestmentManager public immutable investmentManager;

    /// @notice Oracle contract that provides updates to the beacon chain's state
    IBeaconChainOracle public beaconChainOracle;

    event BeaconOracleUpdated(address newOracleAddress);

    modifier onlyEigenPod(address podOwner) {
        require(address(getPod(podOwner)) == msg.sender, "EigenPodManager.onlyEigenPod: not a pod");
        _;
    }

    modifier onlyInvestmentManager {
        require(msg.sender == address(investmentManager), "EigenPodManager.onlyEigenPod: not investmentManager");
        _;
    }

    constructor(IETHPOSDeposit _ethPOS, IBeacon _eigenPodBeacon, IInvestmentManager _investmentManager) {
        ethPOS = _ethPOS;
        eigenPodBeacon = _eigenPodBeacon;
        investmentManager = _investmentManager;
        _disableInitializers();
    }

    function initialize(IBeaconChainOracle _beaconChainOracle, address initialOwner) public initializer {
        beaconChainOracle = _beaconChainOracle;
        emit BeaconOracleUpdated(address(_beaconChainOracle));
        _transferOwnership(initialOwner);
    }

    /**
     * @notice Creates an EigenPod for the sender.
     * @dev Function will revert if the `msg.sender` already has an EigenPod.
     */
    function createPod() external {
        require(!hasPod(msg.sender), "EigenPodManager.createPod: Sender already has a pod");
        //deploy a pod if the sender doesn't have one already
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
        IEigenPod pod = getPod(msg.sender);
        if(!hasPod(msg.sender)) {
            //deploy a pod if the sender doesn't have one already
            pod = _deployPod();
        }
        pod.stake{value: msg.value}(pubkey, signature, depositDataRoot);
    }

    /**
     * @notice Freezes `podOwner`.
     * @param podOwner The restaker to freeze.
     * @dev Callable only by the `podOwner`'s EigenPod.
     */
    function freezeOperator(address podOwner) external onlyEigenPod(podOwner) {
        investmentManager.slasher().freezeOperator(podOwner);
    }

    /**
     * @notice Withdraws ETH that has been withdrawn from the beacon chain from the EigenPod.
     * @param podOwner The owner of the pod whose balance must be withdrawn.
     * @param recipient The recipient of withdrawn ETH.
     * @param amount The amount of ETH to withdraw.
     * @dev Callable only by the InvestmentManager contract.
     */
    function withdrawBeaconChainETH(address podOwner, address recipient, uint256 amount) external onlyInvestmentManager {
        getPod(podOwner).withdrawBeaconChainETH(recipient, amount);
    }

    /**
     * @notice Updates the oracle contract that provides the beacon chain state root
     * @param newBeaconChainOracle is the new oracle contract being pointed to
     * @dev Callable only by the owner of the InvestmentManager (i.e. governance).
     */
    function updateBeaconChainOracle(IBeaconChainOracle newBeaconChainOracle) external onlyOwner {
        beaconChainOracle = newBeaconChainOracle;
        emit BeaconOracleUpdated(address(newBeaconChainOracle));
    }


    // INTERNAL FUNCTIONS
    function _deployPod() internal returns (IEigenPod) {
        IEigenPod pod = 
            IEigenPod(
                Create2.deploy(
                    0, 
                    bytes32(uint256(uint160(msg.sender))), 
                    // set the beacon address to the eigenPodBeacon and initialize it
                    abi.encodePacked(
                        type(BeaconProxy).creationCode, 
                        abi.encode(eigenPodBeacon, abi.encodeWithSelector(IEigenPod.initialize.selector, IEigenPodManager(address(this)), msg.sender))
                    )
                )
            );
        return pod;
    }

    // VIEW FUNCTIONS
    /// @notice Returns the address of the `podOwner`'s EigenPod (whether it is deployed yet or not).
    function getPod(address podOwner) public view returns (IEigenPod) {
        return IEigenPod(
                Create2.computeAddress(
                    bytes32(uint256(uint160(podOwner))), //salt
                    keccak256(abi.encodePacked(
                        type(BeaconProxy).creationCode, 
                        abi.encode(eigenPodBeacon, abi.encodeWithSelector(IEigenPod.initialize.selector, IEigenPodManager(address(this)), podOwner))
                    )) //bytecode
                ));
    }

    /// @notice Returns 'true' if the `podOwner` has created an EigenPod, and 'false' otherwise.
    function hasPod(address podOwner) public view returns (bool) {
        return address(getPod(podOwner)).code.length > 0;
    }

    function getBeaconChainStateRoot() external view returns(bytes32){
        return beaconChainOracle.getBeaconChainStateRoot();
    }
}