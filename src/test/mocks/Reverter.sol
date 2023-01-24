// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

contract Reverter {

    fallback() external {
        revert("Reverter: I am a contract that always reverts");
    }
}