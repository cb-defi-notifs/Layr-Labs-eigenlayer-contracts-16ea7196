// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IServiceManager.sol";
import "../interfaces/IDelayedService.sol";
import "../interfaces/IRegistry.sol";
import "../interfaces/IEphemeralKeyRegistry.sol";
import "../interfaces/IBLSPublicKeyCompendium.sol";
import "../libraries/BytesLib.sol";
import "./BLSRegistry.sol";

// import "forge-std/Test.sol";

/**
 * @title Adds Proof of Custody functionality to the `BLSRegistry` contract.
 * @author Layr Labs, Inc.
 * @notice See the Dankrad's excellent article for an intro to Proofs of Custody:
 * https://dankradfeist.de/ethereum/2021/09/30/proofs-of-custody.html.
 * This contract relies on an `EphemeralKeyRegistry` to store operator's ephemeral keys.
 */
contract BLSRegistryWithBomb is BLSRegistry {
    using BytesLib for bytes;

    IEphemeralKeyRegistry public immutable ephemeralKeyRegistry;

    constructor(
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager,
        IServiceManager _serviceManager,
        uint8 _NUMBER_OF_QUORUMS,
        uint32 _UNBONDING_PERIOD,
        IBLSPublicKeyCompendium _pubkeyCompendium,
        IEphemeralKeyRegistry _ephemeralKeyRegistry
    )
        BLSRegistry(
            _delegation,
            _investmentManager,
            _serviceManager,
            _NUMBER_OF_QUORUMS,
            _UNBONDING_PERIOD,
            _pubkeyCompendium
        )
    {
        ephemeralKeyRegistry = _ephemeralKeyRegistry;
    }

    /**
     * @notice called for registering as an operator.
     * For detailed comments, see the `registerOperator` function in BLSRegistry.sol.
     * same as `BLSRegistry.registerOperator` except adds an external call to `ephemeralKeyRegistry.postFirstEphemeralKeyHash(msg.sender, ephemeralKeyHash)`,
     * passing along the additional argument `ephemeralKeyHash`.
     */
    function registerOperator(
        uint8 operatorType,
        bytes32 ephemeralKeyHash1,
        bytes32 ephemeralKeyHash2,
        bytes calldata pkBytes,
        string calldata socket
    ) external {
        _registerOperator(msg.sender, operatorType, pkBytes, socket);

        ephemeralKeyRegistry.postFirstEphemeralKeyHashes(msg.sender, ephemeralKeyHash1, ephemeralKeyHash2);
    }

    /** 
     * @notice same as RegistryBase._removeOperator except the serveUntil and revokeSlashingAbility updates are moved until later
     *         this is to account for the BLOCK_STALE_MEASURE serving delay needed for EIGENDA
     */
    function _removeOperator(address, bytes32 pubkeyHash, uint32 index) internal override {
        //remove the operator's stake
        uint32 updateBlockNumber = _removeOperatorStake(pubkeyHash);

        // store blockNumber at which operator index changed (stopped being applicable)
        pubkeyHashToIndexHistory[pubkeyHash][pubkeyHashToIndexHistory[pubkeyHash].length - 1].toBlockNumber =
            uint32(block.number);

        // remove the operator at `index` from the `operatorList`
        address swappedOperator = _popRegistrant(index);

        registry[msg.sender].status = IQuorumRegistry.Status.INACTIVE;
        registry[msg.sender].deregisterTime = uint32(block.timestamp);

        // Emit `Deregistration` event
        emit Deregistration(msg.sender, swappedOperator);

        emit StakeUpdate(
            msg.sender,
            // new stakes are zero
            0,
            0,
            uint32(block.number),
            updateBlockNumber
        );
    }

    /** 
     * @notice used to complete deregistration process, revealing the operators final ephemeral keys.
     *         This is the operator's final interaction with the middleware. The operator has already initiated their deregistration,
     *         and now they are revealing their final ephemeral keys to start their bomb period, after which slashing ability will be revoked
     *         and pending withdrawals will be unencumbered by this middleware.
     * @param startIndex the index to start revealing epehemeral keys from
     * @param ephemeralKeys the list of ephemeral keys to be revealed from startIndex to the last one used
     */
    function completeDeregistrationAndRevealLastEphemeralKeys(uint256 startIndex, bytes32[] memory ephemeralKeys) external {
        require(_isAfterDelayedServicePeriod(msg.sender), 
            "BLSRegistryWithBomb.completeDeregistrationAndRevealLastEphemeralKeys: delayed service must pass before completing deregistration");

        // @notice Registrant must continue to serve until the latest time at which an active task expires. this info is used in challenges
        uint32 latestTime = serviceManager.latestTime();
        registry[msg.sender].serveUntil = latestTime;
        // committing to not signing off on any more middleware tasks
        registry[msg.sender].status = IQuorumRegistry.Status.INACTIVE;
        registry[msg.sender].deregisterTime = uint32(block.timestamp);

        // Add ephemeral key(s) to ephemeral key registry
        ephemeralKeyRegistry.revealLastEphemeralKeys(msg.sender, startIndex, ephemeralKeys);

        // Record a stake update unbonding the operator at `latestTime`
        serviceManager.recordLastStakeUpdate(msg.sender, latestTime);

        /**
         * Revoke the slashing ability of the service manager after `latestTime`.
         * This is done after recording the last stake update since `latestTime` *could* be in the past, and `recordLastStakeUpdate` is permissioned so that
         * only contracts who can actively slash the operator are allowed to call it.
         */
        serviceManager.revokeSlashingAbility(msg.sender, latestTime);
    }

    /** 
     * @notice used to propagate a stake update to the Slasher essentially freeing up staked assets for withdrawals have been initiated before blockNumber
     * @param operator the entity whose stake update is being propagated
     * @param ephemeralKeyIndex the index of the ephemeral key that was active at the latest serving block of the stake during blockNumber
     * @param blockNumber the blockNumber which the stake update is being propagated for
     * @param prevElement a helper parameter needed for correct insertion into the linked list living in the Slasher
     */
    function propagateStakeUpdate(address operator, uint32 ephemeralKeyIndex, uint32 blockNumber, uint256 prevElement) external {
        bytes32 pubkeyHash = registry[operator].pubkeyHash;
        require(pubkeyHashToStakeHistory[pubkeyHash][pubkeyHashToStakeHistory[pubkeyHash].length - 1].updateBlockNumber > blockNumber, 
            "BLSRegistryWithBomb.propagateStakeUpdate: stake updates must have occured since blockNumber");

        IServiceManager serviceManager = serviceManager;
        /**
         * Ensure that *strictly more than* BLOCK_STALE_MEASURE blocks have passed since the block we are updating for.
         * This is because the middleware can look `BLOCK_STALE_MEASURE` blocks into the past, i.e. [block.number - BLOCK_STALE_MEASURE, block.number]
         * (i.e. inclusive of the end of the interval), which means that the operator must serve tasks beginning in [block.number, block.number + BLOCK_STALE_MEASURE]
         * (again, inclusive of the interval ends).
         */
        uint32 latestServingBlockNumber = blockNumber + IDelayedService(address(serviceManager)).BLOCK_STALE_MEASURE();
        require(latestServingBlockNumber < uint32(block.number),
            "BLSRegistryWithBomb.propagateStakeUpdate: blockNumber must be BLOCK_STALE_MEASURE blocks ago");
        // @notice Registrant must continue to serve until the latest time at which an active task expires.
        uint32 serveUntil = serviceManager.latestTime();
        // make sure operator revealed all epehemeral keys used when signing blocks that were being served by the specified stake
        require(ephemeralKeyRegistry.getEphemeralKeyEntryAtBlock(operator, ephemeralKeyIndex, latestServingBlockNumber).revealBlock != 0,
            "BLSRegistryWithBomb.propagateStakeUpdate: ephemeral key was not revealed yet");
        //record the stake update in the slasher
        serviceManager.recordStakeUpdate(operator, blockNumber, serveUntil, prevElement);
    }

    function isActiveOperator(address operator) external view override(IRegistry, RegistryBase) returns (bool) {
        //the operator status must be active and they must still be serving or have started their deregistration
        //but still before their final ephemeral key reveal
        /// @dev Fetch operator's stored pubkeyHash
        bytes32 pubkeyHash = registry[operator].pubkeyHash;
        return 
            (registry[operator].status == IQuorumRegistry.Status.ACTIVE && 
                (
                    pubkeyHashToIndexHistory[pubkeyHash][pubkeyHashToIndexHistory[pubkeyHash].length - 1].toBlockNumber == 0 ||
                    pubkeyHashToIndexHistory[pubkeyHash][pubkeyHashToIndexHistory[pubkeyHash].length - 1].toBlockNumber 
                        + IDelayedService(address(serviceManager)).BLOCK_STALE_MEASURE() >= uint32(block.number)
                )
            );
    }

    // the following function overrides the base function of BLSRegistry -- we want operators to provide additional arguments, so these versions (without those args) revert
    function registerOperator(uint8, bytes calldata, string calldata) external pure override {
        revert("BLSRegistryWithBomb.registerOperator: must register with ephemeral key");
    }

    /**
     * @notice this function makes sure the operator hash started their deregistration and that they have passed their delayed 
     *         service period after starting the deregistration process
     */ 
    function _isAfterDelayedServicePeriod(address operator) internal view returns (bool) {
        /// @dev Fetch operator's stored pubkeyHash
        bytes32 pubkeyHash = registry[operator].pubkeyHash;
        uint32 blockNumber = pubkeyHashToIndexHistory[pubkeyHash][pubkeyHashToIndexHistory[pubkeyHash].length - 1].toBlockNumber;
        return blockNumber != 0 && blockNumber + IDelayedService(address(serviceManager)).BLOCK_STALE_MEASURE() < uint32(block.number);
    }
}
