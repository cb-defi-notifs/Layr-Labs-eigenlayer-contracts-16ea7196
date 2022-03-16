// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

//note that this contract does not initialize the governor itself. an inheriting contract should use _transferGovernor in its constructor/initializer
abstract contract Governed {
    address public governor;
    
    modifier onlyGovernor() {
        require(msg.sender == governor, "onlyGovernor");
        _;
    }

    event GovernorTransferred(address indexed oldGovernor, address indexed newGovernor);

    function transferGovernor(address newGovernor) external onlyGovernor {
        _transferGovernor(newGovernor);
    }

    function _transferGovernor(address newGovernor) internal {
        emit GovernorTransferred(governor, newGovernor);
        governor = newGovernor;
    }
}