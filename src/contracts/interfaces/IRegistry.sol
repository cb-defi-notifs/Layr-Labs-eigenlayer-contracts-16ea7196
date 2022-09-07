// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9.0;

interface IRegistry {
    function isRegistered(address operator) external view returns (bool);
}
