// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9.0;

import "@openzeppelin-upgrades/contracts/security/PausableUpgradeable.sol";
import "../interfaces/IPauserRegistry.sol";

contract Pausable is PausableUpgradeable{

    // modifier onlyPauser {
    //     require(msg.sender == IPauserRegistry(address(dlsm)).pauser());
    // }

    //every contract has its own pausing functionality, ie, its own pause() and unpause() functiun
    // those functions are permissioned as "onlyPauser"  which refers to a Pauser Registry

    IPauserRegistry public pauserRegistry;

    modifier onlyPauser {
        require(msg.sender == pauserRegistry.pauser(),  "msg.sender is not permissioned as pauser");
        _;
    }

    modifier onlyUnpauser {
        require(msg.sender == pauserRegistry.unpauser(), "msg.sender is not permissioned as unpauser");
        _;
    }

    function _initializePauser(
        IPauserRegistry _pauserRegistry
    ) internal {
        require(address(pauserRegistry) == address(0) && address(_pauserRegistry) != address(0), "Pausable._initializePauser: _initializePauser() can only be called once");
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
