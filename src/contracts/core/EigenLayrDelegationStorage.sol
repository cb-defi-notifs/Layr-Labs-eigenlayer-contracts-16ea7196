// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IDelegationTerms.sol";
import "../interfaces/IEigenLayrDelegation.sol";

/**
 * @title Storage variables for the `EigenLayrDelegation` contract.
 * @author Layr Labs, Inc.
 * @notice This storage contract is separate from the logic to simplify the upgrade process.
 */
abstract contract EigenLayrDelegationStorage is IEigenLayrDelegation {
    /// @notice Gas budget provided in calls to DelegationTerms contracts
    uint256 internal constant LOW_LEVEL_GAS_BUDGET = 1e5;

    /// @notice Maximum value that `undelegationFraudproofInterval` may take
    uint256 internal constant MAX_UNDELEGATION_FRAUD_PROOF_INTERVAL = 7 days;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegator,address operator,uint256 nonce,uint256 expiry)");

    /// @notice EIP-712 Domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @notice The InvestmentManager contract for EigenLayr
    IInvestmentManager public investmentManager;

    /// @notice The fraudproof interval for undelegation, defined in seconds.
    uint256 public undelegationFraudproofInterval;

    // operator => investment strategy => num shares delegated
    mapping(address => mapping(IInvestmentStrategy => uint256)) public operatorShares;

    // operator => delegation terms contract
    mapping(address => IDelegationTerms) public delegationTerms;

    // staker => operator
    mapping(address => address) public delegation;

    // staker => UTC time at which undelegation is finalized
    mapping(address => uint256) public undelegationFinalizedTime;

    // staker => UTC time at which undelegation was initialized
    mapping(address => uint256) public undelegationInitTime;

    // staker => whether they are delegated or not
    mapping(address => IEigenLayrDelegation.DelegationStatus) public delegated;

    // delegator => number of signed delegation nonce (used in delegateToBySignature)
    mapping(address => uint256) public nonces;

    constructor() {
        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, bytes("EigenLayr"), block.chainid, address(this)));
    }
}
