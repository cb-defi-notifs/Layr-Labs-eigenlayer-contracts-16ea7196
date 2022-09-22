// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "./IInvestmentStrategy.sol";
import "./ISlasher.sol";
import "./IEigenLayrDelegation.sol";
import "./IServiceManager.sol";

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

    function depositIntoStrategy(IInvestmentStrategy strategies, IERC20 token, uint256 amount)
        external
        returns (uint256);

    function withdrawFromStrategy(
        uint256 strategyIndex,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 shareAmount
    )
        external;

    function investorStratShares(address user, IInvestmentStrategy strategy) external view returns (uint256 shares);

    function getDeposits(address depositor) external view returns (IInvestmentStrategy[] memory, uint256[] memory);

    function investorStratsLength(address investor) external view returns (uint256);

    function queueWithdrawal(
        uint256[] calldata strategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        WithdrawerAndNonce calldata withdrawerAndNonce
    )
        external returns(bytes32);

    function startQueuedWithdrawalWaitingPeriod(
        address depositor,
        bytes32 withdrawalRoot,
        uint32 stakeInactiveAfter
    ) external;

    function completeQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        address depositor,
        WithdrawerAndNonce calldata withdrawerAndNonce,
        bool receiveAsTokens
    )
        external;

    function challengeQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        address depositor,
        WithdrawerAndNonce calldata withdrawerAndNonce,
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
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        address slashedAddress,
        address recipient,
        WithdrawerAndNonce calldata withdrawerAndNonce
    )
        external;

    function canCompleteQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        address depositor,
        WithdrawerAndNonce calldata withdrawerAndNonce
    )
        external
        returns (bool);

    function calculateWithdrawalRoot(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts,
        WithdrawerAndNonce calldata withdrawerAndNonce
    )
        external
        pure
        returns (bytes32);

    function delegation() external view returns (IEigenLayrDelegation);

    function slasher() external view returns (ISlasher);
}
