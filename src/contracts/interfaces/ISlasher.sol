// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/**
 * @title Interface for the primary 'slashing' contract for EigenLayr.
 * @author Layr Labs, Inc.
 * @notice See the `Slasher` contract itself for implementation details.
 */
interface ISlasher {
    struct MiddlewareTimes {
        // The update block for the middleware whose most recent update was earliest, i.e. the 'stalest' update
        uint32 leastRecentUpdateBlock;
        // The latest 'serve until' time from all of the middleware that the operator is serving
        uint32 latestServeUntil;
    }

    /**
     * @notice Gives the `contractAddress` permission to slash the funds of the caller.
     * @dev Typically, this function must be called prior to registering for a middleware.
     */
    function allowToSlash(address contractAddress) external;

    /// @notice Called by a contract to revoke its ability to slash `operator`, once `unbondedAfter` is reached.
    function revokeSlashingAbility(address operator, uint32 unbondedAfter) external;

    /**
     * @notice Used for 'slashing' a certain operator.
     * @param toBeFrozen The operator to be frozen.
     * @dev Technically the operator is 'frozen' (hence the name of this function), and then subject to slashing pending a decision by a human-in-the-loop.
     * @dev The operator must have previously given the caller (which should be a contract) the ability to slash them, through a call to `allowToSlash`.
     */
    function freezeOperator(address toBeFrozen) external;

    /**
     * @notice Used to determine whether `staker` is actively 'frozen'. If a staker is frozen, then they are potentially subject to
     * slashing of their funds, and cannot cannot deposit or withdraw from the investmentManager until the slashing process is completed
     * and the staker's status is reset (to 'unfrozen').
     * @return Returns 'true' if `staker` themselves has their status set to frozen, OR if the staker is delegated
     * to an operator who has their status set to frozen. Otherwise returns 'false'.
     */
    function isFrozen(address staker) external view returns (bool);

    /// @notice Returns true if `slashingContract` is currently allowed to slash `toBeSlashed`.
    function canSlash(address toBeSlashed, address slashingContract) external view returns (bool);

    /// @notice Returns the UTC timestamp until which `slashingContract` is allowed to slash the `operator`.
    function bondedUntil(address operator, address slashingContract) external view returns (uint32);

    /**
     * @notice Returns 'true' if `operator` can currently complete a withdrawal started at the `withdrawalStartBlock`, with `middlewareTimesIndex` used
     * to specify the index of a `MiddlewareTimes` struct in the operator's list (i.e. an index in `operatorToMiddlewareTimes[operator]`). The specified
     * struct is consulted as proof of the `operator`'s ability (or lack thereof) to complete the withdrawal.
     * This function will return 'false' if the operator cannot currently complete a withdrawal started at the `withdrawalStartBlock`, *or* in the event
     * that an incorrect `middlewareTimesIndex` is supplied, even if one or more correct inputs exist.
     * @param operator Either the operator who queued the withdrawal themselves, or if the withdrawing party is a staker who delegated to an operator,
     * this address is the operator *who the staker was delegated to* at the time of the `withdrawalStartBlock`.
     * @param withdrawalStartBlock The block number at which the withdrawal was initiated.
     * @param middlewareTimesIndex Indicates an index in `operatorToMiddlewareTimes[operator]` to consult as proof of the `operator`'s ability to withdraw
     * @dev The correct `middlewareTimesIndex` input should be computable off-chain.
     */
    function canWithdraw(address operator, uint32 withdrawalStartBlock, uint256 middlewareTimesIndex) external returns(bool);

    /**
     * @notice this function is a called by middlewares during an operator's registration to make sure the operator's stake at registration 
     *         is slashable until serveUntil
     * @param operator the operator whose stake update is being recorded
     * @param serveUntil the timestamp until which the operator's stake at the current block is slashable
     * @dev adds the middleware's slashing contract to the operator's linked list
     */
    function recordFirstStakeUpdate(address operator, uint32 serveUntil) external;

    /**
     * @notice this function is a called by middlewares during a stake update for an operator (perhaps to free pending withdrawals)
     *         to make sure the operator's stake at updateBlock is slashable until serveUntil
     * @param operator the operator whose stake update is being recorded
     * @param updateBlock the block for which the stake update is being recorded
     * @param serveUntil the timestamp until which the operator's stake at updateBlock is slashable
     * @param insertAfter the element of the operators linked list that the currently updating middleware should be inserted after
     * @dev insertAfter should be calculated offchain before making the transaction that calls this. this is subject to race conditions, 
     *      but it is anticipated to be rare and not detrimental.
     */
    function recordStakeUpdate(address operator, uint32 updateBlock, uint32 serveUntil, uint256 insertAfter) external;

    /**
     * @notice this function is a called by middlewares during an operator's deregistration to make sure the operator's stake at deregistration 
     *         is slashable until serveUntil
     * @param operator the operator whose stake update is being recorded
     * @param serveUntil the timestamp until which the operator's stake at the current block is slashable
     * @dev removes the middleware's slashing contract to the operator's linked list
     */
    function recordLastStakeUpdate(address operator, uint32 serveUntil) external;

    /**
     * @notice Removes the 'frozen' status from each of the `frozenAddresses`
     * @dev Callable only by the contract owner (i.e. governance).
     */
    function resetFrozenStatus(address[] calldata frozenAddresses) external;

    /**
     * @notice Used to give global slashing permission to `contracts`.
     * @dev Callable only by the contract owner (i.e. governance).
     */
    function addGloballyPermissionedContracts(address[] calldata contracts) external;

    /**
     * @notice Used to revoke global slashing permission from `contracts`.
     * @dev Callable only by the contract owner (i.e. governance).
     */
    function removeGloballyPermissionedContracts(address[] calldata contracts) external;

    /// @notice Getter function for fetching `operatorToMiddlewareTimes[operator][index].leastRecentUpdateBlock`.
    function getMiddlewareTimesIndexBlock(address operator, uint32 index) external view returns(uint32);

    /// @notice Getter function for fetching `operatorToMiddlewareTimes[operator][index].latestServeUntil`.
    function getMiddlewareTimesIndexServeUntil(address operator, uint32 index) external view returns(uint32);
}
