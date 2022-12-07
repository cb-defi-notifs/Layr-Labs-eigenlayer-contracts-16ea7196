// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IInvestmentStrategy.sol";
import "../interfaces/IEigenPodManager.sol";
import "../interfaces/IEigenLayrDelegation.sol";
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
    IEigenLayrDelegation public immutable delegation;
    IEigenPodManager public immutable eigenPodManager;
    ISlasher public immutable slasher;

    // staker => InvestmentStrategy => number of shares which they currently hold
    mapping(address => mapping(IInvestmentStrategy => uint256)) public investorStratShares;
    // staker => array of strategies in which they have nonzero shares
    mapping(address => IInvestmentStrategy[]) public investorStrats;
    // hash of withdrawal inputs, aka 'withdrawalRoot' => whether the withdrawal is pending
    mapping(bytes32 => bool) public withdrawalRootPending;
    // staker => cumulative number of queued withdrawals they have ever initiated. only increments (doesn't decrement)
    mapping(address => uint256) public numWithdrawalsQueued;

    IInvestmentStrategy public constant beaconChainETHStrategy = IInvestmentStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0);


    constructor(IEigenLayrDelegation _delegation, IEigenPodManager _eigenPodManager, ISlasher _slasher) {
        delegation = _delegation;
        eigenPodManager = _eigenPodManager;
        slasher = _slasher;
    }
}
