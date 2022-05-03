// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IDataLayrVoteWeigher {
    function setLatestTime(uint32) external;

    function getOperatorId(address) external returns (uint32);

    function getOperatorFromDumpNumber(address) external view returns (uint32);

    function getOperatorType(address operator) external view returns (uint8);

    function apk_x() external view returns (uint256);

    function apk_y() external view returns (uint256);

    function pubkeyHashToStakeHistory(bytes32, uint256) external view returns (uint32, uint32, uint96, uint96);

    function getCorrectCompressedApk(uint256, uint32) external view returns(bytes memory);
}
