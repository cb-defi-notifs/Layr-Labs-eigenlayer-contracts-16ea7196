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
import "../interfaces/IBeaconChainETHReceiver.sol";

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

    /// @notice EigenLayer's Slasher contract
    ISlasher immutable slasher;

    /// @notice Oracle contract that provides updates to the beacon chain's state
    IBeaconChainOracle public beaconChainOracle;
    
    /// @notice Pod owner to the amount of penalties they have paid that are still in this contract
    mapping(address => uint256) public podOwnerToPaidPenalties;

    event BeaconOracleUpdated(address newOracleAddress);

    modifier onlyEigenPod(address podOwner) {
        require(address(getPod(podOwner)) == msg.sender, "EigenPodManager.onlyEigenPod: not a pod");
        _;
    }

    modifier onlyInvestmentManager {
        require(msg.sender == address(investmentManager), "EigenPodManager.onlyInvestmentManager: not investmentManager");
        _;
    }

    modifier onlySlasher {
        require(msg.sender == address(slasher), "EigenPodManager.onlySlasher: not slasher");
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
     * @notice Deposits/Restakes beacon chain ETH in EigenLayer on behalf of the owner of an EigenPod.
     * @param podOwner The owner of the pod whose balance must be deposited.
     * @param amount The amount of ETH to deposit.
     * @dev Callable only by the podOwner's EigenPod contract.
     */
    function restakeBeaconChainETH(address podOwner, uint256 amount) external onlyEigenPod(podOwner) {
        investmentManager.depositBeaconChainETH(podOwner, amount);
    }

    /**
     * @notice Removes beacon chain ETH from EigenLayer on behalf of the owner of an EigenPod, when the
     *         balance of a validator is lower than how much stake they have committed to EigenLayer
     * @param podOwner The owner of the pod whose balance must be removed.
     * @param amount The amount of ETH to remove.
     * @dev Callable only by the podOwner's EigenPod contract.
     */
    function recordOvercommittedBeaconChainETH(address podOwner, uint256 beaconChainETHStrategyIndex, uint256 amount) external onlyEigenPod(podOwner) {
        investmentManager.recordOvercommittedBeaconChainETH(podOwner, beaconChainETHStrategyIndex, amount);
    }

    /**
     * @notice Withdraws ETH from an EigenPod. The ETH must have first been withdrawn from the beacon chain.
     * @param podOwner The owner of the pod whose balance must be withdrawn.
     * @param recipient The recipient of withdrawn ETH.
     * @param amount The amount of ETH to withdraw.
     * @dev Callable only by the InvestmentManager contract.
     */
    function withdrawRestakedBeaconChainETH(address podOwner, address recipient, uint256 amount) external onlyInvestmentManager {
        getPod(podOwner).withdrawRestakedBeaconChainETH(recipient, amount);
    }

    /**
     * @notice Sends ETH from the EigenPod to the EigenPodManager in order to fullfill its penalties to EigenLayer
     * @param podOwner The owner of the pod whose balance is being sent.
     * @dev Callable only by the podOwner's pod.
     */
    function payPenalties(address podOwner) external payable onlyEigenPod(podOwner) {
        podOwnerToPaidPenalties[podOwner] += msg.value;
    }

    /**
     * @notice Withdraws penalties of a certain pod
     * @param recipient The recipient of withdrawn ETH.
     * @param amount The amount of ETH to withdraw.
     * @dev Callable only by the slasher.
     */
    function withdrawPenalties(address podOwner, address recipient, uint256 amount) external onlySlasher {
        podOwnerToPaidPenalties[podOwner] -= amount;
        // transfer penalties from pod to `recipient`
        if (Address.isContract(recipient)) {
            // if the recipient is a contract, then call its `receiveBeaconChainETH` function
            IBeaconChainETHReceiver(recipient).receiveBeaconChainETH{value: amount}();
        } else {
            // if the recipient is an EOA, then do a simple transfer
            payable(recipient).transfer(amount);
        }
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