// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IDelayedService {
    function BLOCK_STALE_MEASURE() external view returns(uint32);    
}
