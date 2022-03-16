// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

abstract contract Initializable {
    bool internal initialized;
    
    //should be attached to the initializer function. otherwise all hell could break loose.
    modifier initializer() {
        require(!initialized, "already initialized");
        _;
        initialized = true;
    }
}