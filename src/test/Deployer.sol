// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../contracts/core/EigenLayrDelegation.sol";
import "../contracts/core/EigenLayrDeposit.sol";
import "../contracts/investment/EigenLayrDeposit.sol";
import "../contracts/core/EigenLayrDeposit.sol";

import "../contracts/core/Eigen.sol";


contract EigenLayrDeployer {
    Eigen public eigen;
    constructor() {
        eigen = new Eigen();
        //do stuff this eigen token here
        
    }
}