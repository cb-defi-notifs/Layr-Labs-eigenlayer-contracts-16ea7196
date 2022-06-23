// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./IDataLayr.sol";


interface IDataLayrEphemeralKeyRegistry{

    function postEphemeralKeyPreImage(bytes memory prevEK, bytes memory currEKHash) external;

    function getCurrEphemeralKeyHash(address DataLayrNode, bytes memory EKHash) external;

    function verifyEphemeralKeyIntegrity(bytes memory ephemeralKey) external;


}