// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC165.sol";

contract ERC165 is IERC165 {
    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}