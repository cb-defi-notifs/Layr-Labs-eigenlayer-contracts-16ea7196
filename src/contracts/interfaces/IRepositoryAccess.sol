// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IRepository.sol";

interface IRepositoryAccess {
    function repository() external view returns(IRepository);
}