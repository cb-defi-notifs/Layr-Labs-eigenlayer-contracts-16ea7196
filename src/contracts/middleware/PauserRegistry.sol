// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9.0;


import "../interfaces/IPauserRegistry.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";



abstract contract PauserRegistry is IPauserRegistry, OwnableUpgradeable{

    address public pauser;
    address public unpauser;

    constructor(
        address _pauser,
        address _unpauser
    ){
        pauser = _pauser;
        unpauser = _unpauser;
    }

    function setPauser(address newPauser) external onlyOwner {
        pauser = newPauser;
    }
    function setUnPauser(address newUnpauser) external onlyOwner {
        unpauser = newUnpauser;
    }
}