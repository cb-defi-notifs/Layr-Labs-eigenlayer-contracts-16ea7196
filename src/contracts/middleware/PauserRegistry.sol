// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "../interfaces/IPauserRegistry.sol";


contract PauserRegistry is IPauserRegistry {

    address public pauser;
    address public unpauser;

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
    }


    function setPauser(address newPauser) external onlyPauser {
        pauser = newPauser;
    }

    function setUnpauser(address newUnpauser) external onlyUnpauser {
        unpauser = newUnpauser;
    }



}