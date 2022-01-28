// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IOperatorPermitter {
    function operatorPermitted(address operator) external returns (bool);
}