// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9.0;

interface IPauserRegistry {
    function pauser() external returns (address);
    function unpauser() external returns (address);
}
