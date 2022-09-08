// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9.0;

import "@openzeppelin-upgrades/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/access/AccessControlUpgradeable.sol";

contract Pausable is PausableUpgradeable, AccessControlUpgradeable{

    bytes32 public constant PAUSER = keccak256("PAUSER");
    bytes32 public constant UNPAUSER = keccak256("UNPAUSER");


    function _initializePause(
        address pauser, 
        address unpauser
    ) internal onlyInitializing {
        
        __Pausable_init();
        __AccessControl_init();
        _grantRole(PAUSER, pauser);
        _grantRole(UNPAUSER, unpauser);
    }

    /**
     * @notice This function is used to pause an EigenLayer/DataLayer
     *         contract functionality.  It is permissioned to the "PAUSER"
     *         address, which is a low threshold multisig.
     */  
    function pause() public onlyRole(PAUSER) {
        _pause();
    }

    /**
     * @notice This function is used to unpause an EigenLayer/DataLayer
     *         contract functionality.  It is permissioned to the "UNPAUSER"
     *         address, which is a reputed committee controlled, high threshold 
     *         multisig.
     */  
    function unpause() public onlyRole(UNPAUSER) {
        _unpause();
    }
}
