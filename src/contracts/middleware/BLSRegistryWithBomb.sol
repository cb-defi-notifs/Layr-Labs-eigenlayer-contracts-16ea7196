// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "../interfaces/IServiceManager.sol";
import "../interfaces/IRegistry.sol";
import "../interfaces/IEphemeralKeyRegistry.sol";
import "../libraries/BytesLib.sol";
import "./BLSRegistry.sol";

import "forge-std/Test.sol";

/**
 * @title Adds Proof of Custody functionality to the `BLSRegistry` contract.
 * @author Layr Labs, Inc.
 * @notice See the Dankrad's excellent article for an intro to Proofs of Custody:
 * https://dankradfeist.de/ethereum/2021/09/30/proofs-of-custody.html.
 * This contract relies on an `EphemeralKeyRegistry` to store operator's ephemeral keys.
 */
contract BLSRegistryWithBomb is
    BLSRegistry
    // ,DSTest
{
    using BytesLib for bytes;

    IEphemeralKeyRegistry public ephemeralKeyRegistry;

    constructor(
        Repository _repository,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager,
        IEphemeralKeyRegistry _ephemeralKeyRegistry,
        uint8 _NUMBER_OF_QUORUMS,
        uint256[] memory _quorumBips,
        StrategyAndWeightingMultiplier[] memory _firstQuorumStrategiesConsideredAndMultipliers,
        StrategyAndWeightingMultiplier[] memory _secondQuorumStrategiesConsideredAndMultipliers
    )
        BLSRegistry(
            _repository,
            _delegation,
            _investmentManager,
            _NUMBER_OF_QUORUMS,
            _quorumBips,
            _firstQuorumStrategiesConsideredAndMultipliers,
            _secondQuorumStrategiesConsideredAndMultipliers
        )
    {
        ephemeralKeyRegistry = _ephemeralKeyRegistry;
    }

    /**
      @notice Used by an operator to de-register itself from providing service to the middleware.
              For detailed comments, see deregisterOperator in BLSRegistry.sol.
     */
    function deregisterOperator(uint256[4] memory pubkeyToRemoveAff, uint32 index, bytes32 finalEphemeralKey) external returns (bool) {
        _deregisterOperator(msg.sender, pubkeyToRemoveAff, index);

        //post last ephemeral key reveal on chain
        ephemeralKeyRegistry.postLastEphemeralKeyPreImage(msg.sender, finalEphemeralKey);
        
        return true;
    }

    /**
     @notice called for registering as an operator. For detailed comments, see 
             registerOperator in BLSRegistry.sol.
     */
    function registerOperator(
        uint8 operatorType,
        bytes32 ephemeralKeyHash,
        bytes calldata data,
        string calldata socket
    ) external {        
        _registerOperator(msg.sender, operatorType, data, socket);

        //add ephemeral key to ephemeral key registry
        ephemeralKeyRegistry.postFirstEphemeralKeyHash(msg.sender, ephemeralKeyHash);
    }

    // the following function overrides the base function of BLSRegistry -- we want operators to provide additional arguments, so these versions (without those args) revert
    function registerOperator(
        uint8,
        bytes calldata,
        string calldata
    ) external override pure {        
        revert("BLSRegistryWithBomb.registerOperator: must register with ephemeral key");
    }

    // the following function overrides the base function of BLSRegistry -- we want operators to provide additional arguments, so these versions (without those args) revert
    function deregisterOperator(uint256[4] memory, uint32) external override pure returns (bool) {
        revert("BLSRegistryWithBomb.deregisterOperator: must deregister with ephemeral key");
    }
}