// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IEigenLayrFeePayer {
    function explanation() external returns (string memory);
    function redeem(uint256 queryId) external;
    function addQuery(uint256 queryId) external;
    event Payout(bytes32 queryId, address indexed to);
}

interface IEigenLayrVoteWeigher {
    function weightOf(address registrant) external returns (uint256);
}

interface IEigenLayrService {
    function feePayer() external returns (IEigenLayrFeePayer);
    function voteWeigher() external returns (IEigenLayrVoteWeigher);
    function explanation() external returns (string memory);
    function register() external;
    function commitDeregister() external;
    function deregister() external;
    function initQuery(bytes calldata queryData) external returns (uint256);
    function voteOnNewAnswer(uint256 queryId, bytes calldata answerBytes) external returns (bytes32);
    function voteOnAnswer(uint256 queryId, bytes32 answerHash) external;
    function resolveAnswer(uint256 queryId) external;
}