// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IInvestmentStrategy.sol";
import "../interfaces/IEigenPodManager.sol";
import "../interfaces/IEigenLayerDelegation.sol";
import "../interfaces/ISlasher.sol";

/**
 * @title Storage variables for the `InvestmentManager` contract.
 * @author Layr Labs, Inc.
 * @notice This storage contract is separate from the logic to simplify the upgrade process.
 */
abstract contract InvestmentManagerStorage is IInvestmentManager {
    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    /// @notice The EIP-712 typehash for the deposit struct used by the contract
    bytes32 public constant DEPOSIT_TYPEHASH =
        keccak256("Deposit(address strategy,address token,uint256 amount,uint256 nonce,uint256 expiry)");
    /// @notice EIP-712 Domain separator
    bytes32 public DOMAIN_SEPARATOR;
    // staker => number of signed deposit nonce (used in depositIntoStrategyOnBehalfOf)
    mapping(address => uint256) public nonces;

    // maximum length of dynamic arrays in `investorStrats` mapping, for sanity's sake
    uint8 internal constant MAX_INVESTOR_STRATS_LENGTH = 32;

    // system contracts
    IEigenLayerDelegation public immutable delegation;
    IEigenPodManager public immutable eigenPodManager;
    ISlasher public immutable slasher;

    /// @notice Mapping: staker => InvestmentStrategy => number of shares which they currently hold
    mapping(address => mapping(IInvestmentStrategy => uint256)) public investorStratShares;
    /// @notice Mapping: staker => array of strategies in which they have nonzero shares
    mapping(address => IInvestmentStrategy[]) public investorStrats;
    /// @notice Mapping: hash of withdrawal inputs, aka 'withdrawalRoot' => whether the withdrawal is pending
    mapping(bytes32 => bool) public withdrawalRootPending;
    /// @notice Mapping: staker => cumulative number of queued withdrawals they have ever initiated. only increments (doesn't decrement)
    mapping(address => uint256) public numWithdrawalsQueued;
    /// @notice Mapping: strategy => whether or not stakers are allowed to deposit into it
    mapping(IInvestmentStrategy => bool) public strategyIsWhitelistedForDeposit;
    /*
     * @notice Mapping: staker => virtual 'beaconChainETH' shares that the staker 'owes' due to overcommitments of beacon chain ETH.
     * When overcommitment is proven, `InvestmentManager.recordOvercommittedBeaconChainETH` is called. However, it is possible that the
     * staker already queued a withdrawal for more beaconChainETH shares than the `amount` input to this function. In this edge case,
     * the amount that cannot be decremented is added to the staker's `beaconChainETHWithdrawalDebt` -- then when the staker completes a
     * withdrawal of beaconChainETH, the amount they are withdrawing is first decreased by their `beaconChainETHWithdrawalDebt` amount.
     * In other words, a staker's `beaconChainETHWithdrawalDebt` must be 'paid down' before they can "actually withdraw" beaconChainETH.
     * @dev In practice, this means not passing a call to `eigenPodManager.withdrawRestakedBeaconChainETH` until the staker's 
     * `beaconChainETHWithdrawalDebt` has first been 'paid off'.
    */
    mapping(address => uint256) public beaconChainETHWithdrawalDebt;

    IInvestmentStrategy public constant beaconChainETHStrategy = IInvestmentStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0);

    constructor(IEigenLayerDelegation _delegation, IEigenPodManager _eigenPodManager, ISlasher _slasher) {
        delegation = _delegation;
        eigenPodManager = _eigenPodManager;
        slasher = _slasher;
    }
}
