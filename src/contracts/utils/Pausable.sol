// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9.0;

import "../interfaces/IPauserRegistry.sol";

import "forge-std/Test.sol";

contract Pausable {

    // modifier onlyPauser {
    //     require(msg.sender == IPauserRegistry(address(dlsm)).pauser());
    // }

    //every contract has its own pausing functionality, ie, its own pause() and unpause() functiun
    // those functions are permissioned as "onlyPauser"  which refers to a Pauser Registry

    IPauserRegistry public pauserRegistry;

    bool private _paused;

    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);


    modifier onlyPauser {
        require(msg.sender == pauserRegistry.pauser(),  "msg.sender is not permissioned as pauser");
        _;
    }

    modifier onlyUnpauser {
        require(msg.sender == pauserRegistry.unpauser(), "msg.sender is not permissioned as unpauser");
        _;
    }

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    function _initializePauser(
        IPauserRegistry _pauserRegistry
    ) internal {

        require(
            address(pauserRegistry) == address(0) && 
            address(_pauserRegistry) != address(0), 
            "Pausable._initializePauser: _initializePauser() can only be called once"
        );

        _paused = false;
        pauserRegistry = _pauserRegistry;
        
    }

    /**
     * @notice This function is used to pause an EigenLayer/DataLayer
     *         contract functionality.  It is permissioned to the "PAUSER"
     *         address, which is a low threshold multisig.
     */  
    function pause() public onlyPauser {
        _paused = true;

        emit Paused(msg.sender);
    }

    /**
     * @notice This function is used to unpause an EigenLayer/DataLayer
     *         contract functionality.  It is permissioned to the "UNPAUSER"
     *         address, which is a reputed committee controlled, high threshold 
     *         multisig.
     */  
    function unpause() public onlyUnpauser {
        _paused = false;

        emit Unpaused(msg.sender);
    }

    

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        require(!paused(), "Pausable: paused");
    }
}
