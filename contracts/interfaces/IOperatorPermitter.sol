// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IOperatorPermitter {
    function operatorPermitted(address operator) external returns (bool);
}