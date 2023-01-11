// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IEigenLayerDelegation.sol";
import "../interfaces/IEigenPodManager.sol";
import "../interfaces/IETHPOSDeposit.sol";
import "../interfaces/IEigenPod.sol";
import "../interfaces/IBeaconChainOracle.sol";

// import "forge-std/Test.sol";

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
    IETHPOSDeposit public immutable ethPOS;
    
    /// @notice Beacon proxy to which the EigenPods point
    IBeacon public immutable eigenPodBeacon;

    /// @notice EigenLayer's InvestmentManager contract
    IInvestmentManager public immutable investmentManager;

    /// @notice EigenLayer's Slasher contract
    ISlasher public immutable slasher;

    /// @notice Oracle contract that provides updates to the beacon chain's state
    IBeaconChainOracle public beaconChainOracle;
    
    /// @notice Pod owner to the amount of penalties they have paid that are still in this contract
    mapping(address => uint256) public podOwnerToUnwithdrawnPaidPenalties;

    /// @notice Emitted to notify the update of the beaconChainOracle address
    event BeaconOracleUpdated(address indexed newOracleAddress);

    /// @notice Emitted to notify the deployment of an EigenPod
    event PodDeployed(address indexed eigenPod, address indexed podOwner);

    /// @notice Emitted to notify a deposit of beacon chain ETH recorded in the investment manager
    event BeaconChainETHDeposited(address indexed podOwner, uint256 amount);

    /// @notice Emitted when an EigenPod pays penalties, on behalf of its owner
    event PenaltiesPaid(address indexed podOwner, uint256 amountPaid);

    modifier onlyEigenPod(address podOwner) {
        require(address(getPod(podOwner)) == msg.sender, "EigenPodManager.onlyEigenPod: not a pod");
        _;
    }

    modifier onlyInvestmentManager {
        require(msg.sender == address(investmentManager), "EigenPodManager.onlyInvestmentManager: not investmentManager");
        _;
    }

    constructor(IETHPOSDeposit _ethPOS, IBeacon _eigenPodBeacon, IInvestmentManager _investmentManager, ISlasher _slasher) {
        ethPOS = _ethPOS;
        eigenPodBeacon = _eigenPodBeacon;
        investmentManager = _investmentManager;
        slasher = _slasher;
        _disableInitializers();
    }

    function initialize(IBeaconChainOracle _beaconChainOracle, address initialOwner) public initializer {
        _updateBeaconChainOracle(_beaconChainOracle);
        _transferOwnership(initialOwner);
    }

    /**
     * @notice Creates an EigenPod for the sender.
     * @dev Function will revert if the `msg.sender` already has an EigenPod.
     */
    function createPod() external {
        require(!hasPod(msg.sender), "EigenPodManager.createPod: Sender already has a pod");
        //deploy a pod if the sender doesn't have one already
        IEigenPod pod = _deployPod();

        emit PodDeployed(address(pod), msg.sender);
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
     * @notice Deposits/Restakes beacon chain ETH in EigenLayer on behalf of the owner of an EigenPod.
     * @param podOwner The owner of the pod whose balance must be deposited.
     * @param amount The amount of ETH to 'deposit' (i.e. be credited to the podOwner).
     * @dev Callable only by the podOwner's EigenPod contract.
     */
    function restakeBeaconChainETH(address podOwner, uint256 amount) external onlyEigenPod(podOwner) {
        investmentManager.depositBeaconChainETH(podOwner, amount);
        emit BeaconChainETHDeposited(podOwner, amount);
    }

    /**
     * @notice Removes beacon chain ETH from EigenLayer on behalf of the owner of an EigenPod, when the
     *         balance of a validator is lower than how much stake they have committed to EigenLayer
     * @param podOwner The owner of the pod whose balance must be removed.
     * @param amount The amount of beacon chain ETH to decrement from the podOwner's shares in the investmentManager.
     * @dev Callable only by the podOwner's EigenPod contract.
     */
    function recordOvercommittedBeaconChainETH(address podOwner, uint256 beaconChainETHStrategyIndex, uint256 amount) external onlyEigenPod(podOwner) {
        investmentManager.recordOvercommittedBeaconChainETH(podOwner, beaconChainETHStrategyIndex, amount);
    }

    /**
     * @notice Withdraws ETH from an EigenPod. The ETH must have first been withdrawn from the beacon chain.
     * @param podOwner The owner of the pod whose balance must be withdrawn.
     * @param recipient The recipient of the withdrawn ETH.
     * @param amount The amount of ETH to withdraw.
     * @dev Callable only by the InvestmentManager contract.
     */
    function withdrawRestakedBeaconChainETH(address podOwner, address recipient, uint256 amount) external onlyInvestmentManager {
        getPod(podOwner).withdrawRestakedBeaconChainETH(recipient, amount);
    }

    /**
     * @notice Records receiving ETH from the `PodOwner`'s EigenPod, paid in order to fullfill the EigenPod's penalties to EigenLayer
     * @param podOwner The owner of the pod whose balance is being sent.
     * @dev Callable only by the podOwner's EigenPod contract.
     */
    function payPenalties(address podOwner) external payable onlyEigenPod(podOwner) {
        podOwnerToUnwithdrawnPaidPenalties[podOwner] += msg.value;
        emit PenaltiesPaid(podOwner, msg.value);
    }

    /**
     * @notice Withdraws paid penalties of the `podOwner`'s EigenPod, to the `recipient` address
     * @param recipient The recipient of withdrawn ETH.
     * @param amount The amount of ETH to withdraw.
     * @dev Callable only by the investmentManager.owner().
     */
    function withdrawPenalties(address podOwner, address recipient, uint256 amount) external {
        require(msg.sender == Ownable(address(investmentManager)).owner(), "EigenPods.withdrawPenalties: only investmentManager owner");
        podOwnerToUnwithdrawnPaidPenalties[podOwner] -= amount;
        // transfer penalties from pod to `recipient`
        Address.sendValue(payable(recipient), amount);
    }

    /**
     * @notice Updates the oracle contract that provides the beacon chain state root
     * @param newBeaconChainOracle is the new oracle contract being pointed to
     * @dev Callable only by the owner of this contract (i.e. governance)
     */
    function updateBeaconChainOracle(IBeaconChainOracle newBeaconChainOracle) external onlyOwner {
        _updateBeaconChainOracle(newBeaconChainOracle);
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

    function _updateBeaconChainOracle(IBeaconChainOracle newBeaconChainOracle) internal {
        beaconChainOracle = newBeaconChainOracle;
        emit BeaconOracleUpdated(address(newBeaconChainOracle));
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