// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IRegistry.sol";

interface IDataLayrRegistry is IRegistry {
// TODO: decide if this struct is better defined in 'IRegistry', 'IDataLayrRegistry', or a separate file
/*
    struct OperatorStake {
        uint32 updateBlockNumber;
        uint32 nextUpdateBlockNumber;
        uint96 ethStake;
        uint96 eigenStake;
    }
*/
    // function setLatestTime(uint32 _latestTime) external;

    function getOperatorId(address operator) external returns (uint32);

    function getFromDataStoreIdForOperator(address operator) external view returns (uint32);
        
    // function getOperatorStatus(address operator) external view returns(uint8);

    function getLengthOfTotalStakeHistory() external view returns (uint256);
    
    function getOperatorIndex(address operator, uint32 dataStoreId, uint32 index) external view returns (uint32);

    function getTotalOperators(uint32 dataStoreId, uint32 index) external view returns (uint32);
    
    function getDLNStatus(address DLN) external view returns (uint8);

    function getOperatorDeregisterTime(address operator) external view returns (uint256);

    function operatorStakes(address operator) external view returns (uint96, uint96);

    function totalStake() external view returns (uint96, uint96);

    function totalEthStaked() external view returns (uint96);

    function totalEigenStaked() external view returns (uint96);
}
