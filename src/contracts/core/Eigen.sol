// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract Eigen is ERC1155 {
    constructor(address _recipient) ERC1155("https://layrlabs.org") {
        _mint(_recipient, 0, 1000e18, "");
    }
}