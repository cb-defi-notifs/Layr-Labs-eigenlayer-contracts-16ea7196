// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "../interfaces/IPauserRegistry.sol";


contract PauserRegistry is IPauserRegistry {

    address public pauser;
    address public unpauser;

    event PauserChanged (
        address newPauser
    );

    event UnpauserChanged (
        address newUnpauser
    );

    modifier onlyPauser {
        require(msg.sender == pauser,  "msg.sender is not permissioned as pauser");
        _;
    }

    modifier onlyUnpauser {
        require(msg.sender == unpauser, "msg.sender is not permissioned as unpauser");
        _;
    }

    constructor(
        address _pauser,
        address _unpauser
    ) {
        pauser = _pauser;
        unpauser = _unpauser;


        emit PauserChanged(pauser);
        emit UnpauserChanged(unpauser);
        
    }

    //sets new pauser - only callable by unpauser, as the unpauser has a higher threshold
    function setPauser(address newPauser) external onlyUnpauser {
        require(newPauser != address(0) && pauser != address(0), "pauser has not been inititalized by registry");
        pauser = newPauser;

        emit PauserChanged(newPauser);
    }

    function setUnpauser(address newUnpauser) external onlyUnpauser {
        require(newUnpauser != address(0) && unpauser != address(0), "unpauser has not been inititalized by registry");
        unpauser = newUnpauser;

        emit UnpauserChanged(newUnpauser);
    }
}