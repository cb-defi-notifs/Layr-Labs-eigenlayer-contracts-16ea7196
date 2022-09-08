// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9.0;

interface IPauseRegistry {
    function isRegistered(address operator) external view returns (bool);
}