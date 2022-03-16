// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

library SafeERC20 {
    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));
    bytes4 private constant TRANSFER_FROM_SELECTOR = bytes4(keccak256(bytes("transferFrom(address,address,uint256)")));
    bytes4 private constant APPROVE_SELECTOR = bytes4(keccak256(bytes("approve(address,uint256)")));
    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(TRANSFER_SELECTOR, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "_safeTransfer failed");
    }
    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(TRANSFER_FROM_SELECTOR, from, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "_safeTransferFrom failed");
    }
    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(APPROVE_SELECTOR, spender, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "_safeApprove failed");
    }
}