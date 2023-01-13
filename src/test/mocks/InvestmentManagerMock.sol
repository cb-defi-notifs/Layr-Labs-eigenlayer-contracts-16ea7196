// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../contracts/permissions/Pausable.sol";
import "../../contracts/core/InvestmentManagerStorage.sol";
import "../../contracts/interfaces/IServiceManager.sol";
import "../../contracts/interfaces/IEigenPodManager.sol";
import "../../contracts/interfaces/IEigenLayerDelegation.sol";

// import "forge-std/Test.sol";

contract InvestmentManagerMock is
    Initializable,
    IInvestmentManager,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    Pausable
    // ,Test
{

    IEigenLayerDelegation public immutable delegation;
    IEigenPodManager public immutable eigenPodManager;
    ISlasher public immutable slasher;

    constructor(IEigenLayerDelegation _delegation, IEigenPodManager _eigenPodManager, ISlasher _slasher)
    {
       delegation = _delegation;
       slasher = _slasher;
       eigenPodManager = _eigenPodManager;

    }

    function depositIntoStrategy(IInvestmentStrategy strategy, IERC20 token, uint256 amount)
        external
        returns (uint256){}


    function depositBeaconChainETH(address staker, uint256 amount) external{}


    function recordOvercommittedBeaconChainETH(address overcommittedPodOwner, uint256 beaconChainETHStrategyIndex, uint256 amount)
        external{}

    function depositIntoStrategyOnBehalfOf(
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 amount,
        address staker,
        uint256 expiry,
        bytes memory signature
    )
        external
        returns (uint256 shares){}

    /// @notice Returns the current shares of `user` in `strategy`
    function investorStratShares(address user, IInvestmentStrategy strategy) external view returns (uint256 shares){}

    /**
     * @notice Get all details on the depositor's investments and corresponding shares
     * @return (depositor's strategies, shares in these strategies)
     */
    function getDeposits(address depositor) external view returns (IInvestmentStrategy[] memory, uint256[] memory){}

    /// @notice Simple getter function that returns `investorStrats[staker].length`.
    function investorStratsLength(address staker) external view returns (uint256){}


    function queueWithdrawal(
        uint256[] calldata strategyIndexes,
        StratsTokensShares calldata sts,
        address withdrawer,
        bool undelegateIfPossible
    )
        external returns(bytes32){}


    function completeQueuedWithdrawal(
        QueuedWithdrawal calldata queuedWithdrawal,
        uint256 middlewareTimesIndex,
        bool receiveAsTokens
    )
        external{}


    function slashShares(
        address slashedAddress,
        address recipient,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata strategyIndexes,
        uint256[] calldata shareAmounts
    )
        external{}

    /**
     * @notice Slashes an existing queued withdrawal that was created by a 'frozen' operator (or a staker delegated to one)
     * @param recipient The funds in the slashed withdrawal are withdrawn as tokens to this address.
     */
    function slashQueuedWithdrawal(
        address recipient,
        QueuedWithdrawal calldata queuedWithdrawal
    )
        external{}

    /// @notice Returns the keccak256 hash of `queuedWithdrawal`.
    function calculateWithdrawalRoot(
        QueuedWithdrawal memory queuedWithdrawal
    )
        external
        pure
        returns (bytes32){}

    /// @notice returns the enshrined beaconChainETH Strategy
    function beaconChainETHStrategy() external view returns (IInvestmentStrategy){}
}

