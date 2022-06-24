// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./IDataLayr.sol";

interface IDataLayrEphemeralKeyRegistry {
    function postEphemeralKeyPreImage(
        bytes32 prevEK,
        bytes32 currEKHash
    ) external;

    function getCurrEphemeralKeyHash(address dataLayrNode)
        external
        returns (bytes32);

    function getLatestEphemeralKey(address dataLayrNode)
        external
        returns (bytes32);

    function verifyEphemeralKeyIntegrity(bytes32 ephemeralKey) external;

    function postFirstEphemeralKeyPreImage(address, bytes32) external;
}
