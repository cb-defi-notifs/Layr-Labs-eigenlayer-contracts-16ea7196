// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "../interfaces/IETHPOSDeposit.sol";
import "../interfaces/IEigenPod.sol";

contract EigenPodFactory {
    //TODO: change this to constant in prod
    IETHPOSDeposit immutable ethPOS;
    IBeacon immutable eigenPodBeacon;

    struct EigenPodInfo {
        IEigenPod pod;
        uint256 stake;
    }

    mapping(address => EigenPodInfo) public pods;

    constructor(IETHPOSDeposit _ethPOS, IBeacon _eigenPodBeacon) {
        ethPOS = _ethPOS;
        eigenPodBeacon = _eigenPodBeacon;
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
                        abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(eigenPodBeacon, hex""))
                    )
                );
            pods[msg.sender].pod = pod;
        }
        //stake on the pod
        pod.stake{value: msg.value}(pubkey, signature, depositDataRoot);
    }
}