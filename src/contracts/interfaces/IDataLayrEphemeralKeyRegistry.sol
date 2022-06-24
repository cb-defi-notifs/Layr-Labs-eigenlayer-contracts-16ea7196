// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./IDataLayr.sol";


interface IDataLayrEphemeralKeyRegistry{

    function postEphemeralKeyPreImage(bytes memory prevEK, bytes memory currEKHash) external;

    function getCurrEphemeralKeyHash(address dataLayrNode) external returns(bytes32);

    function verifyEphemeralKeyIntegrity(address dataLayrNode, bytes32 ephemeralKey) external;


}