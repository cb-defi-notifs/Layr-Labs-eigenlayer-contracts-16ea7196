// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IDelegationTerms.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IServiceFactory.sol";
import "../investment/Slasher.sol";

abstract contract EigenLayrDelegationStorage is IEigenLayrDelegation {
    IInvestmentManager public investmentManager;

    IServiceFactory public serviceFactory;

    // TODO: refer to another place for this address (in particular, the InvestmentManager?), so we do not have multiple places to update it?
    Slasher public slasher;

    // operator => investment strategy => num shares delegated
    mapping(address => mapping(IInvestmentStrategy => uint256)) public operatorShares;

    // staker => hash of delegated strategies
    mapping(address => bytes32) public delegatedStrategiesHash;

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

    // TODO: decide if these DOMAIN_TYPEHASH and DELEGATION_TYPEHASHes are acceptable/appropriate
    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegator,address operator,uint256 nonce,uint256 expiry)");

    // delegator => number of signed delegation nonce (used in delegateToBySignature)
    mapping(address => uint256) delegationNonces;
}
