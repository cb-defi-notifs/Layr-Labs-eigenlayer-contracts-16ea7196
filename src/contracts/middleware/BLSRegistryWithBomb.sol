// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

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
        StrategyAndWeightingMultiplier[] memory _ethStrategiesConsideredAndMultipliers,
        StrategyAndWeightingMultiplier[] memory _eigenStrategiesConsideredAndMultipliers
    )
        BLSRegistry(
            _repository,
            _delegation,
            _investmentManager,
            _ethStrategiesConsideredAndMultipliers,
            _eigenStrategiesConsideredAndMultipliers
        )
    {
        ephemeralKeyRegistry = _ephemeralKeyRegistry;
    }

    /**
      @notice Used by an operator to de-register itself from providing service to the middleware.
     */
    /** 
      @param pubkeyToRemoveAff is the sender's pubkey in affine coordinates
     */
    function deregisterOperator(uint256[4] memory pubkeyToRemoveAff, uint32 index, bytes32 finalEphemeralKey) external returns (bool) {
        _deregisterOperator(pubkeyToRemoveAff, index);
        //post last ephemeral key reveal on chain
        ephemeralKeyRegistry.postFirstEphemeralKeyHash(msg.sender, finalEphemeralKey);
        return true;
    }

    /**
     @notice called for registering as an operator
     */
    /**
     @param registrantType specifies whether the operator want to register as ETH staker or Eigen stake or both
     @param data is the calldata that contains the coordinates for pubkey on G2 and signature on G1
     @param socket is the socket address of the operator
     
     */ 
    function registerOperator(
        uint8 registrantType,
        bytes32 ephemeralKey,
        bytes calldata data,
        string calldata socket
    ) external {        
        _registerOperator(msg.sender, registrantType, data, socket);
        //add ephemeral key to epehemral key registry
        ephemeralKeyRegistry.postFirstEphemeralKeyHash(msg.sender, ephemeralKey);
    }

    function registerOperator(
        uint8,
        bytes calldata,
        string calldata
    ) public override pure {        
        revert("must register with ephemeral key");
    }

    function deregisterOperator(uint256[4] memory, uint32) external override pure returns (bool) {
        revert("must deregister with ephemeral key");
        return false;
    }
}