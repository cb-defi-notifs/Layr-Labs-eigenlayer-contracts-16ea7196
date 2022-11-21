// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../contracts/interfaces/IServiceManager.sol";
import "../../contracts/interfaces/IQuorumRegistry.sol";
import "../../contracts/interfaces/IInvestmentManager.sol";
import "../../contracts/interfaces/IEphemeralKeyRegistry.sol";


import "forge-std/Test.sol";




contract EigenDARegistryMock is IQuorumRegistry, DSTest{
    IServiceManager public immutable serviceManager;
    IInvestmentManager public immutable investmentManager;
    IEphemeralKeyRegistry public immutable ephemeralKeyRegistry;


    constructor(
        IServiceManager _serviceManager,
        IInvestmentManager _investmentManager,
        IEphemeralKeyRegistry _ephemeralKeyRegistry
    ){
        serviceManager = _serviceManager;
        investmentManager = _investmentManager;
        ephemeralKeyRegistry = _ephemeralKeyRegistry;
    }

    function registerOperator(
        address operator, 
        uint32 serveUntil,
        bytes32 ephemeralKeyHash1,
        bytes32 ephemeralKeyHash2
    ) public {        
        require(investmentManager.slasher().canSlash(operator, address(serviceManager)), "Not opted into slashing");
        serviceManager.recordFirstStakeUpdate(operator, serveUntil);
        ephemeralKeyRegistry.postFirstEphemeralKeyHashes(msg.sender, ephemeralKeyHash1, ephemeralKeyHash2);
    }

    function deregisterOperator(
        address operator,
        bytes32[] memory ephemeralKeys,
        uint256 startIndex
    ) public {
        uint32 latestTime = serviceManager.latestTime();
        serviceManager.recordLastStakeUpdate(operator, latestTime);
        ephemeralKeyRegistry.revealLastEphemeralKeys(msg.sender, startIndex, ephemeralKeys);

    }

    function propagateStakeUpdate(address operator, uint32 blockNumber, uint256 prevElement) external {
        uint32 serveUntil = serviceManager.latestTime();
        serviceManager.recordStakeUpdate(operator, blockNumber, serveUntil, prevElement);
    }

     function isActiveOperator(address operator) external pure returns (bool) {
        if (operator != address(0)){
            return true;
        } else {
            return false;
        }
     }

    function getLengthOfTotalStakeHistory() external view returns (uint256){}

    function getTotalStakeFromIndex(uint256 index) external view returns (OperatorStake memory){}

    /// @notice Returns the unique ID of the specified `operator`.
    function getOperatorId(address operator) external returns (uint32){}

    /// @notice Returns the stored pubkeyHash for the specified `operator`.
    function getOperatorPubkeyHash(address operator) external view returns (bytes32){}

    /// @notice Returns task number from when `operator` has been registered.
    function getFromTaskNumberForOperator(address operator) external view returns (uint32){}

    /// @notice Returns block number from when `operator` has been registered.
    function getFromBlockNumberForOperator(address operator) external view returns (uint32){}

    function getStakeFromPubkeyHashAndIndex(bytes32 pubkeyHash, uint256 index) external view returns (OperatorStake memory){}

    function getOperatorIndex(address operator, uint32 blockNumber, uint32 index) external view returns (uint32){}

    function getTotalOperators(uint32 blockNumber, uint32 index) external view returns (uint32){}

    function numOperators() external view returns (uint32){}
    function getOperatorDeregisterTime(address operator) external view returns (uint256){}

    function operatorStakes(address operator) external view returns (uint96, uint96){}

    /// @notice Returns the stake amounts from the latest entry in `totalStakeHistory`.
    function totalStake() external view returns (uint96, uint96){}
}