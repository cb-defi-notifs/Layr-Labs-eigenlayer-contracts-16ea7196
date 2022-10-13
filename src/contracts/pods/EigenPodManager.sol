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

    modifier onlyInvestmentManager(address addr) {
        require(addr == address(investmentManager), "EigenPodManager.onlyEigenPod: not investmentManager");
        _;
    }

    constructor(IETHPOSDeposit _ethPOS, IBeacon _eigenPodBeacon, IInvestmentManager _investmentManager) {
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
        uint128 newBalance = pods[podOwner].balance - balanceToRemove + balanceToAdd;
        pods[podOwner].balance = newBalance;
        //if the balance updates shows that the pod owner has more deposits than beacon chain balance, freeze them
        //TODO: add EigenPoManager as globally permissioned slashing contract
        if(pods[podOwner].stakeDeposited > newBalance) {
            investmentManager.slasher().freezeOperator(podOwner);
        }
    }

    function depositBalanceIntoEigenLayer(address podOwner, uint128 amount) external onlyInvestmentManager(msg.sender) {
        //make sure that the podOwner hasn't over committed their stake, and deposit on their behalf
        require(pods[podOwner].balance + amount <= pods[podOwner].stakeDeposited, "EigenPodManager.depositBalanceIntoEigenLayer: cannot deposit more than balance");
        pods[podOwner].stakeDeposited += amount;
    }

    function withdrawBeaconChainBalance(address podOwner, uint256 amount) external onlyInvestmentManager(msg.sender) {
        IEigenPod withdrawerPod = pods[podOwner].pod;
        withdrawerPod.withdrawEther(podOwner, amount);
    }

    // VIEW FUNCTIONS

    function getPod(address podOwner) external view returns (EigenPodInfo memory) {
        EigenPodInfo memory podInfo = pods[podOwner];
        return podInfo;
    }
}