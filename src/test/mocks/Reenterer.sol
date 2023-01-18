// SPDX-License-Identifier: MIT
// contract is copied from Seaport: https://github.com/ProjectOpenSea/seaport/blob/891b5d4f52b58eb7030597fbb22dca67fd86c4c8/contracts/test/Reenterer.sol
pragma solidity ^0.8.9;

contract Reenterer {
    address public target;
    uint256 public msgValue;
    bytes public callData;

    event Reentered(bytes returnData);

    function prepare(
        address targetToUse,
        uint256 msgValueToUse,
        bytes calldata callDataToUse
    ) external {
        target = targetToUse;
        msgValue = msgValueToUse;
        callData = callDataToUse;
    }

    receive() external payable {
        (bool success, bytes memory returnData) = target.call{
            value: msgValue
        }(callData);

        if (!success) {
            assembly {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }

        emit Reentered(returnData);
    }
}