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

    // TODO: either make this immutable *or* add a method to change it
    IEphemeralKeyRegistry public ephemeralKeyRegistry;

    constructor(
        Repository _repository,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager,
        IEphemeralKeyRegistry _ephemeralKeyRegistry,
        uint32 _unbondingPeriod,
        uint8 _NUMBER_OF_QUORUMS,
        uint256[] memory _quorumBips,
        StrategyAndWeightingMultiplier[] memory _firstQuorumStrategiesConsideredAndMultipliers,
        StrategyAndWeightingMultiplier[] memory _secondQuorumStrategiesConsideredAndMultipliers,
        IBLSPublicKeyCompendium _pubkeyCompendium
    )
        BLSRegistry(
            _repository,
            _delegation,
            _investmentManager,
            _unbondingPeriod,
            _NUMBER_OF_QUORUMS,
            _quorumBips,
            _firstQuorumStrategiesConsideredAndMultipliers,
            _secondQuorumStrategiesConsideredAndMultipliers,
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
     *         this is the operators final interaction with DataLayr. they have already initiated their deregistration,
     *         no they are revealing their final ephemeral keys to start their bomb period, then slashin ability will be revoked
     *         and pending withdrawals are free
     * @param startIndex the index to start revealing epehemeral keys from
     * @param ephemeralKeys the list of ephemeral keys to be revealed from startIndex to the last one used
     */
    function completeDeregistrationAndRevealLastEphemeralKeys(uint256 startIndex, bytes32[] memory ephemeralKeys) internal {
        require(_isAfterDelayedServicePeriod(msg.sender), 
            "BLSRegistryWithBomb.completeDeregistrationAndRevealLastEphemeralKeys: delayed service must pass before completing deregistration");

        // @notice Registrant must continue to serve until the latest time at which an active task expires. this info is used in challenges
        uint32 latestTime = repository.serviceManager().latestTime();
        registry[msg.sender].serveUntil = latestTime;
        // committing to not signing off on any more middleware tasks
        registry[msg.sender].status = IQuorumRegistry.Status.INACTIVE;
        registry[msg.sender].deregisterTime = uint32(block.timestamp);

        //add ephemeral key to ephemeral key registry
        ephemeralKeyRegistry.revealLastEphemeralKeys(msg.sender, startIndex, ephemeralKeys);

        //revoke the slashing ability of the service manager
        repository.serviceManager().revokeSlashingAbility(msg.sender, latestTime);

        // record a stake update not bonding the operator at all (unbonded at 0), because they haven't served anything yet
        repository.serviceManager().recordLastStakeUpdate(msg.sender, latestTime);
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

        IServiceManager serviceManager = repository.serviceManager();
        //make sure BLOCK_STALE_MEASURE blocks have passed since the block we are updating for
        uint32 latestServingBlockNumber = blockNumber + IDelayedService(address(serviceManager)).BLOCK_STALE_MEASURE();
        require(latestServingBlockNumber < uint32(block.number),
            "BLSRegistryWithBomb.propagateStakeUpdate: blockNumber must be BLOCK_STALE_MEASURE blocks ago");
        // @notice Registrant must continue to serve until the latest time at which an active task expires.
        uint32 serveUntil = serviceManager.latestTime();
        //make sure operator revealed all epehemeral keys used when signing blocks that were being served by the specified stake
        require(ephemeralKeyRegistry.getEphemeralKeyEntryAtBlock(operator, ephemeralKeyIndex, latestServingBlockNumber).revealBlock != 0,
            "BLSRegistryWithBomb.propagateStakeUpdate: ephemeral key was not revealed yet");
        //record the stake update in the slasher
        serviceManager.recordStakeUpdate(operator, blockNumber, serveUntil, prevElement);
    }

    function isActiveOperator(address operator) external view override returns (bool) {
        //the operator status must be active and they must still be serving or have started their deregistration
        //but still before their final ephemeral key reveal
        /// @dev Fetch operator's stored pubkeyHash
        bytes32 pubkeyHash = registry[operator].pubkeyHash;
        return 
            (registry[operator].status == IQuorumRegistry.Status.ACTIVE && 
                (
                    pubkeyHashToIndexHistory[pubkeyHash][pubkeyHashToIndexHistory[pubkeyHash].length - 1].toBlockNumber == 0 ||
                    pubkeyHashToIndexHistory[pubkeyHash][pubkeyHashToIndexHistory[pubkeyHash].length - 1].toBlockNumber 
                        + IDelayedService(address(repository.serviceManager())).BLOCK_STALE_MEASURE() >= uint32(block.number)
                )
            );
    }

    // the following function overrides the base function of BLSRegistry -- we want operators to provide additional arguments, so these versions (without those args) revert
    function registerOperator(uint8, bytes calldata, string calldata) external pure override {
        revert("BLSRegistryWithBomb.registerOperator: must register with ephemeral key");
    }

    // the following function overrides the base function of BLSRegistry -- we want operators to provide additional arguments, so these versions (without those args) revert
    function deregisterOperator(uint256[4] memory, uint32) external pure override returns (bool) {
        revert("BLSRegistryWithBomb.deregisterOperator: must deregister with ephemeral key");
    }


    /**
     * @notice this function makes sure the operator hash started their deregistration and that they have passed their delayed 
     *         service period after starting the deregistration process
     */ 
    function _isAfterDelayedServicePeriod(address operator) internal view returns (bool) {
        /// @dev Fetch operator's stored pubkeyHash
        bytes32 pubkeyHash = registry[operator].pubkeyHash;
        uint32 blockNumber = pubkeyHashToIndexHistory[pubkeyHash][pubkeyHashToIndexHistory[pubkeyHash].length - 1].toBlockNumber;
        return blockNumber != 0 && blockNumber + IDelayedService(address(repository.serviceManager())).BLOCK_STALE_MEASURE() < uint32(block.number);
    }
}
