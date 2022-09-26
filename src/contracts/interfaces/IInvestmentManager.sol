// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "./IInvestmentStrategy.sol";
import "./ISlasher.sol";
import "./IEigenLayrDelegation.sol";
import "./IServiceManager.sol";

/**
 * @title Interface for the primary entrypoint for funds into EigenLayr.
 * @author Layr Labs, Inc.
 * @notice See the `InvestmentManager` contract itself for implementation details.
 */
interface IInvestmentManager {
    // used for storing details of queued withdrawals
    struct WithdrawalStorage {
        uint32 initTimestamp;
        uint32 unlockTimestamp;
        address withdrawer;
    }

    // packed struct for queued withdrawals
    struct WithdrawerAndNonce {
        address withdrawer;
        uint96 nonce;
    }

    struct QueuedWithdrawal {
        IInvestmentStrategy[] strategies;
        IERC20[] tokens;
        uint256[] shares;
        address depositor;
        WithdrawerAndNonce withdrawerAndNonce;
        address delegatedAddress;
    }

    function depositIntoStrategy(IInvestmentStrategy strategies, IERC20 token, uint256 amount)
        external
        returns (uint256);

    function investorStratShares(address user, IInvestmentStrategy strategy) external view returns (uint256 shares);

    function getDeposits(address depositor) external view returns (IInvestmentStrategy[] memory, uint256[] memory);

    function investorStratsLength(address investor) external view returns (uint256);

    function queueWithdrawal(
        uint256[] calldata strategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        WithdrawerAndNonce calldata withdrawerAndNonce,
        bool undelegateIfPossible
    )
        external returns(bytes32);

    function startQueuedWithdrawalWaitingPeriod(
        bytes32 withdrawalRoot,
        uint32 stakeInactiveAfter
    ) external;

    function completeQueuedWithdrawal(
        QueuedWithdrawal calldata queuedWithdrawal,
        bool receiveAsTokens
    )
        external;

    function challengeQueuedWithdrawal(
        QueuedWithdrawal calldata queuedWithdrawal,
        bytes calldata data,
        IServiceManager slashingContract
    )
        external;

    function slashShares(
        address slashedAddress,
        address recipient,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata strategyIndexes,
        uint256[] calldata shareAmounts
    )
        external;

    function slashQueuedWithdrawal(
        address recipient,
        QueuedWithdrawal calldata queuedWithdrawal
    )
        external;

    function canCompleteQueuedWithdrawal(
        QueuedWithdrawal calldata queuedWithdrawal
    )
        external
        returns (bool);

    function calculateWithdrawalRoot(
        QueuedWithdrawal memory queuedWithdrawal
    )
        external
        pure
        returns (bytes32);

    function delegation() external view returns (IEigenLayrDelegation);

    function slasher() external view returns (ISlasher);
}
