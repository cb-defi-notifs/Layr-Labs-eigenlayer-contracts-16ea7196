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

    function revealAndUpdateEphemeralKey(
        bytes32 prevEK, 
        bytes32 currEKHash
    ) external;
    
    function getCurrEphemeralKeyHash(address operator)
        external
        returns (bytes32);

    function getLatestEphemeralKey(address operator)
        external
        returns (bytes32);

    function proveStaleUnrevealedEphemeralKey(address operator) external;
 
    function proveLeakedEphemeralKey(address operator, bytes32 leakedEphemeralKey) external;

    function getLastEKPostTimestamp(address operator) external returns (uint192);

    function getEphemeralKeyForTaskNumber(address operator, uint32 taskNumber)
        external view
        returns (bytes32);
}
