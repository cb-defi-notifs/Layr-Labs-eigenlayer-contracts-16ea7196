// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "../interfaces/IServiceManager.sol";
import "../interfaces/IRegistry.sol";
import "../interfaces/IEphemeralKeyRegistry.sol";
import "../libraries/BytesLib.sol";
import "./BLSRegistry.sol";

import "ds-test/test.sol";

/**
 * @notice This contract is used for 
            - registering new operators 
            - committing to and finalizing de-registration as an operator for the middleware 
            - updating the stakes of the operator
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
        StrategyAndWeightingMultiplier[] memory _ethStrategiesConsideredAndMultipliers,
        StrategyAndWeightingMultiplier[] memory _eigenStrategiesConsideredAndMultipliers
    )
        BLSRegistry(
            _repository,
            _delegation,
            _investmentManager,
            _NUMBER_OF_QUORUMS,
            _ethStrategiesConsideredAndMultipliers,
            _eigenStrategiesConsideredAndMultipliers
        )
    {
        ephemeralKeyRegistry = _ephemeralKeyRegistry;
    }

    /**
      @notice Used by an operator to de-register itself from providing service to the middleware.
              For detailed comments, see deregisterOperator in BLSRegistry.sol.
     */
    function deregisterOperator(uint256[4] memory pubkeyToRemoveAff, uint32 index, bytes32 finalEphemeralKey) external returns (bool) {
        _deregisterOperator(pubkeyToRemoveAff, index);

        //post last ephemeral key reveal on chain
        ephemeralKeyRegistry.postLastEphemeralKeyPreImage(msg.sender, finalEphemeralKey);
        
        return true;
    }

    /**
     @notice called for registering as an operator. For detailed comments, see 
             registerOperator in BLSRegistry.sol.
     */
    function registerOperator(
        uint8 registrantType,
        bytes32 ephemeralKeyHash,
        bytes calldata data,
        string calldata socket
    ) external {        
        _registerOperator(msg.sender, registrantType, data, socket);

        //add ephemeral key to ephemeral key registry
        ephemeralKeyRegistry.postFirstEphemeralKeyHash(msg.sender, ephemeralKeyHash);
    }

    // CRITIC  @ChaoticWalrus, @Sidu28 --- what are following funcs for?
    function registerOperator(
        uint8,
        bytes calldata,
        string calldata
    ) public override pure {        
        revert("must register with ephemeral key");
    }

    function deregisterOperator(uint256[4] memory, uint32) external override pure returns (bool) {
        revert("must deregister with ephemeral key");
    }
}