// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IFeeManager.sol";
import "./IVoteWeighter.sol";

interface IQueryManager {
    // struct for storing the amount of Eigen and ETH that has been staked
    struct Stake {
        uint128 eigenStaked;
        uint128 ethStaked;
    }

    function timelock() external view returns (address);

    function operatorCounts() external view returns(uint256);

    function getOpertorCount() public pure view returns(uint32);

    function getOpertorCountOfType(uint8) public pure view returns(uint32);

    function consensusLayerEthToEth() external view returns (uint256);

    function totalEigenStaked() external view returns (uint128);

    function createNewQuery(bytes calldata queryData) external;

    function getQueryDuration() external view returns (uint256);

    function getQueryCreationTime(bytes32) external view returns (uint256);

    function getOperatorType(address) external view returns (uint8);

    function numRegistrants() external view returns (uint256);

    function voteWeighter() external view returns (IVoteWeighter);

    function feeManager() external view returns (IFeeManager);

    function updateStake(address)
        external
        returns (
            uint128,
            uint128
        );

    function eigenStakedByOperator(address) external view returns (uint128);

    function ethStakedByOperator(address) external view returns (uint128);

    function totalEthStaked() external view returns (uint128);

    function ethAndEigenStakedForOperator(address)
        external
        view returns (uint128, uint128);

    function operatorStakes(address) external view returns (uint128, uint128);

    function totalStake() external view returns (uint128, uint128);
}
