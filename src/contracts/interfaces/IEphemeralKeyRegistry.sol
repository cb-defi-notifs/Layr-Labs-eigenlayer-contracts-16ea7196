// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9.0;

interface IEphemeralKeyRegistry {
    function postFirstEphemeralKeyHash(
        address operator,
        bytes32 EKHash
    ) external;

    function postLastEphemeralKeyPreImage(
        address operator,
        bytes32 EK
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
 
    function proveLeakedEphemeralKey(address dataLayrNode, bytes32 leakedEphemeralKey) external;

    function getLastEKPostTimestamp(address dataLayrNode) external returns (uint192);

    function getEphemeralKeyForTaskNumber(address operator, uint32 taskNumber)
        external view
        returns (bytes32);
}
