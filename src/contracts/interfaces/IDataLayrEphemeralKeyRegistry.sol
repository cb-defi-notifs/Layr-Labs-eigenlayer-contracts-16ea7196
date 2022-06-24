// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./IDataLayr.sol";

interface IDataLayrEphemeralKeyRegistry {
    function postEphemeralKeyPreImage(
        bytes memory prevEK,
        bytes memory currEKHash
    ) external;

    function getCurrEphemeralKeyHash(address dataLayrNode)
        external
        returns (bytes32);

    function getLatestEphemeralKey(address dataLayrNode)
        external
        returns (bytes32);

<<<<<<< HEAD
    function verifyEphemeralKeyIntegrity(address dataLayrNode, bytes32 ephemeralKey) external;


}
=======
    function verifyEphemeralKeyIntegrity(bytes memory ephemeralKey) external;
}
>>>>>>> 76db7ece4f41e2422d089f2494654063fe926bca
