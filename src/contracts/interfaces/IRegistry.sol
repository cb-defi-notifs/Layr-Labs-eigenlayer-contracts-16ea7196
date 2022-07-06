// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IRegistry {
// TODO: decide if this struct is better defined in 'IRegistry', 'IDataLayrRegistry', or a separate file
    struct OperatorStake {
        uint32 updateBlockNumber;
        uint32 nextUpdateBlockNumber;
        uint96 ethStake;
        uint96 eigenStake;
    }

    function isRegistered(address operator) external view returns (bool);

    function getTotalStakeFromIndex(uint256 index) external view returns (OperatorStake memory);   

    function getOperatorPubkeyHash(address operator) external view returns (bytes32);

    function getOperatorFromTaskNumber(address operator) external view returns (uint32);

    function getStakeFromPubkeyHashAndIndex(bytes32 pubkeyHash, uint256 index) external view returns (OperatorStake memory);

    function getCorrectApkHash(uint256 index, uint32 blockNumber) external returns (bytes32);

    function getOperatorType(address operator) external view returns (uint8);
}
