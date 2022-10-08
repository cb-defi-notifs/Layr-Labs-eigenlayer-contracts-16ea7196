// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "../interfaces/IEigenPodManager.sol";
import "../interfaces/IETHPOSDeposit.sol";
import "../interfaces/IEigenPod.sol";

contract EigenPodManager is IEigenPodManager {
    //TODO: change this to constant in prod
    IETHPOSDeposit immutable ethPOS;
    
    IBeacon public immutable eigenPodBeacon;

    address public investmentManager;

    struct EigenPodInfo {
        uint128 balance; //total balance of all validators in the pod
        uint128 stakeDeposited; //amount of balance deposited into EigenLayer
        IEigenPod pod;
    }

    mapping(address => EigenPodInfo) public pods;

    constructor(IETHPOSDeposit _ethPOS, IBeacon _eigenPodBeacon, address _investmentManager) {
        ethPOS = _ethPOS;
        eigenPodBeacon = _eigenPodBeacon;
        investmentManager = _investmentManager;
    }
    

    function stake(bytes32 salt, bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable {
        IEigenPod pod = pods[msg.sender].pod;
        if(address(pod) == address(0)) {
            //deploy a pod if the sender doesn't have one already
            pod = 
                IEigenPod(
                    Create2.deploy(
                        0, 
                        salt, 
                        // set the beacon address to the eigenPodBeacon, no initialization data for now
                        abi.encodePacked(
                            type(BeaconProxy).creationCode, 
                            abi.encodeWithSelector(IEigenPod.initialize.selector, IEigenPodManager(address(this)), msg.sender)
                        )
                    )
                );
            pods[msg.sender].pod = pod;
        }
        //stake on the pod
        pod.stake{value: msg.value}(pubkey, signature, depositDataRoot);
    }

    function updateBeaconChainBalance(address podOwner, uint64 balanceToRemove, uint64 balanceToAdd) external onlyEigenPod(podOwner, msg.sender) {
        pods[podOwner].balance = pods[podOwner].balance - balanceToRemove + balanceToAdd;
    }

    function depositBalanceIntoEigenLayer(address podOwner, uint128 amount) external onlyInvestmentManager(msg.sender) {
        //make sure that the podOwner hasn't over committed their stake, and deposit on their behalf
        require(pods[podOwner].balance + amount <= pods[podOwner].stakeDeposited, "EigenPodManager.depositBalanceIntoEigenLayer: Cannot deposit more than balance");
        pods[podOwner].stakeDeposited += amount;
    }

    modifier onlyEigenPod(address podOwner, address pod) {
        require(address(pods[podOwner].pod) == pod, "EigenPodManager.onlyEigenPod: Not a pod");
        _;
    }

    modifier onlyInvestmentManager(address addr) {
        require(addr == investmentManager, "EigenPodManager.onlyEigenPod: Not investmentManager");
        _;
    }
}