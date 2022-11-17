// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../contracts/interfaces/IBeaconChainETHReceiver.sol";


contract BeaconChainETHReceiver is IBeaconChainETHReceiver {

    uint256 public contract_balance;

    function receiveBeaconChainETH() external payable{
        contract_balance += msg.value;
    }

}

