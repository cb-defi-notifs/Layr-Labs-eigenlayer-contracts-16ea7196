// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

/**
 * @title Interface for a `VoteWeigher`-type contract.
 * @author Layr Labs, Inc.
 * @notice Note that `NUMBER_OF_QUORUMS` is expected to remain constant, as suggested by its uppercase formatting.
*/
interface IVoteWeigher {
    function weightOfOperator(address operator, uint256 quorumNumber) external returns (uint96);
    function NUMBER_OF_QUORUMS() external view returns (uint256);
    function quorumBips(uint256 quorumNumber) external view returns (uint256);
}
