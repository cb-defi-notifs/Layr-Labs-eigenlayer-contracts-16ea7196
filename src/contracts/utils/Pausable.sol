// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9.0;

import "@openzeppelin-upgrades/contracts/security/PausableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/access/AccessControlUpgradeable.sol";
import "../interfaces/IPauserRegistry.sol";

contract Pausable is PausableUpgradeable, AccessControlUpgradeable{

    bytes32 public constant PAUSER = keccak256("PAUSER");
    bytes32 public constant UNPAUSER = keccak256("UNPAUSER");

    IPauserRegistry pauserRegistry;

    modifier onlyPauser {
        require(msg.sender == pauserRegistry.pauser());
        _;
    }
    modifier onlyUnpauser {
        require(msg.sender == pauserRegistry.unpauser());
        _;
    }

    //every contract has its own pausing functionality, ie, its own pause() and unpause() functiun
    // those functions are permissioned as "onlyPauser"  which refers to a Pauser Registry

    function _initializePauser(
        IPauserRegistry _pauserRegistry
    ) internal onlyInitializing {
        __Pausable_init();
        pauserRegistry = _pauserRegistry;
    }

    /**
     * @notice This function is used to pause an EigenLayer/DataLayer
     *         contract functionality.  It is permissioned to the "PAUSER"
     *         address, which is a low threshold multisig.
     */  
    function pause() public onlyPauser {
        _pause();
    }

    /**
     * @notice This function is used to unpause an EigenLayer/DataLayer
     *         contract functionality.  It is permissioned to the "UNPAUSER"
     *         address, which is a reputed committee controlled, high threshold 
     *         multisig.
     */  
    function unpause() public onlyUnpauser {
        _unpause();
    }
}
