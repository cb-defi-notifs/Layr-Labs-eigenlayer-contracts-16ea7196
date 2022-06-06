// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IDelegationTerms.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IServiceFactory.sol";

abstract contract EigenLayrDelegationStorage is IEigenLayrDelegation {
    address public constant SELF_DELEGATION_ADDRESS = address(1);

    IInvestmentManager public investmentManager;

    // operator => investment strategy => num shares delegated
    mapping(address => mapping(IInvestmentStrategy => uint256)) public operatorShares;

    mapping(address => uint256) public eigenDelegated;

    // operator => delegation terms contract
    mapping(address => IDelegationTerms) public delegationTerms;

    // staker => operator
    mapping(address => address) public delegation;

    // staker => time of last undelegation commit
    mapping(address => uint256) public lastUndelegationCommit;

    // staker => whether they are delegated or not
    mapping(address => IEigenLayrDelegation.DelegationStatus) public delegated;

    // fraud proof interval for undelegation
    uint256 public undelegationFraudProofInterval;

    // maximum value that 'undelegationFraudProofInterval' may take
    uint256 internal constant MAX_UNDELEGATION_FRAUD_PROOF_INTERVAL = 7 days;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegator,address operator,uint256 nonce,uint256 expiry)");

    /// @notice EIP-712 Domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    // delegator => number of signed delegation nonce (used in delegateToBySignature)
    mapping(address => uint256) nonces;

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(DOMAIN_TYPEHASH, bytes("EigenLayr"), block.chainid)
        );
    }
}
