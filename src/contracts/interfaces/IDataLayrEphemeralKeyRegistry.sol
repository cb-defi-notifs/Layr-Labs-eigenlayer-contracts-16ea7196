// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./IDataLayr.sol";

interface IDataLayrEphemeralKeyRegistry {
    function postFirstEphemeralKeyPreImage(
        address operator,
        bytes32 EKHash
    ) external;

    function updateEphemeralKeyPreImage(
        bytes32 prevEK, 
        bytes32 currEKHash
    ) external;
    
    function getCurrEphemeralKeyHash(address dataLayrNode)
        external
        returns (bytes32);

    function getLatestEphemeralKey(address dataLayrNode)
        external
        returns (bytes32);

    function proveStaleEphemeralKey(address dataLayrNode) external;
 
    function verifyEphemeralKeyIntegrity(address dataLayrNode, bytes32 leakedEphemeralKey) external;

}
