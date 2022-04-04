// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

contract ERC165_Universal is IERC165 {
    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}