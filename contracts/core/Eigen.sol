// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract Eigen is ERC1155 {
    constructor() ERC1155("https://layrlabs.org") {
        _mint(msg.sender, 0, 10**18, "");
    }
}