// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9.0;

import "@openzeppelin-upgrades/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/access/AccessControlUpgradeable.sol";

contract Pausable is PausableUpgradeable, AccessControlUpgradeable{

    bytes32 public constant PAUSER = keccak256("PAUSER");
    bytes32 public constant UNPAUSER = keccak256("UNPAUSER");


    function initializePause(address pauser, address unpauser) internal initializer {

        __Pausable_init();
        __AccessControl_init();
        _grantRole(PAUSER, pauser);
        _grantRole(UNPAUSER, unpauser);
    }



    function pause() public onlyRole(PAUSER) {
        _pause();
    }

    function unpause() public onlyRole(UNPAUSER) {
        _unpause();
    }




}
