// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IEigenPodManager.sol";
import "../interfaces/IETHPOSDeposit.sol";
import "../interfaces/IEigenPod.sol";

contract EigenPodManager is IEigenPodManager {
    //TODO: change this to constant in prod
    IETHPOSDeposit immutable ethPOS;
    
    IBeacon public immutable eigenPodBeacon;

    IInvestmentManager public investmentManager;

    mapping(address => EigenPodInfo) public pods;

    modifier onlyEigenPod(address podOwner, address pod) {
        require(address(pods[podOwner].pod) == pod, "EigenPodManager.onlyEigenPod: not a pod");
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
    }

    function createPod() external {
        require(address(pods[msg.sender].pod) == address(0), "EigenPodManager.createPod: Sender already has a pod");
        //deploy a pod if the sender doesn't have one already
        deployPod();
    }

    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable {
        IEigenPod pod = pods[msg.sender].pod;
        if(address(pod) == address(0)) {
            //deploy a pod if the sender doesn't have one already
            pod = deployPod();
        }
        //stake on the pod
        pod.stake{value: msg.value}(pubkey, signature, depositDataRoot);
    }

    function updateBeaconChainBalance(address podOwner, uint64 balanceToRemove, uint64 balanceToAdd) external onlyEigenPod(podOwner, msg.sender) {
        uint128 newBalance = pods[podOwner].balance - balanceToRemove + balanceToAdd;
        pods[podOwner].balance = newBalance;
        //if the balance updates shows that the pod owner has more deposits into EigenLayer than beacon chain balance, freeze them
        //we also add the balance of of the eigenPod in case withdrawals have occured to validator balances have been set to 0
        //the overall law is 
        ///  the balance of all their validators = balance of the withdrawal address + balance given from beacon chain state root
        //TODO: add EigenPodManager as globally permissioned slashing contract
        if(pods[podOwner].stakedBalance > newBalance + msg.sender.balance) {
            investmentManager.slasher().freezeOperator(podOwner);
        }
    }

    function depositBalanceIntoEigenLayer(address podOwner, uint128 amount) external onlyInvestmentManager {
        //make sure that the podOwner hasn't over committed their stake, and deposit on their behalf
        require(pods[podOwner].balance + amount <= pods[podOwner].stakedBalance, "EigenPodManager.depositBalanceIntoEigenLayer: cannot deposit more than balance");
        pods[podOwner].stakedBalance += amount;
    }

    function withdraw(address podOwner, address recipient, uint256 amount) external onlyInvestmentManager {
        EigenPodInfo memory podInfo = pods[podOwner];
        //subtract withdrawn amount from stake and balance
        pods[podOwner].stakedBalance = podInfo.stakedBalance - uint128(amount);
        podInfo.pod.withdrawETH(recipient, amount);
    }

    // INTERNAL FUNCTIONS

    function deployPod() internal returns (IEigenPod) {
        IEigenPod pod = 
            IEigenPod(
                Create2.deploy(
                    0, 
                    bytes32(uint256(uint160(msg.sender))), 
                    // set the beacon address to the eigenPodBeacon and initialize it
                    abi.encodePacked(
                        type(BeaconProxy).creationCode, 
                        abi.encodeWithSelector(IEigenPod.initialize.selector, IEigenPodManager(address(this)), msg.sender)
                    )
                )
            );
        pods[msg.sender].pod = pod;
        return pod;
    }

    // VIEW FUNCTIONS

    function getPod(address podOwner) external view returns (IEigenPod) {
        return pods[podOwner].pod;
    }

    function getPodInfo(address podOwner) external view returns (EigenPodInfo memory) {
        EigenPodInfo memory podInfo = pods[podOwner];
        return podInfo;
    }
}