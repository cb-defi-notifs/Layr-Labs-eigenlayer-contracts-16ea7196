// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Eigen.sol";
import "../interfaces/IProofOfStakingOracle.sol";
import "../interfaces/IDepositContract.sol";
import "../interfaces/IInvestmentManager.sol";
import "../middleware/Repository.sol";

abstract contract EigenLayrDepositStorage {
    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId, address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DEPOSIT_CLAIM_TYPEHASH = keccak256("DepositClaim(address claimer)");
    
    /// @notice EIP-712 Domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    // delegator => number of signed delegation nonce (used in delegateToBySignature)
    mapping(address => uint256) nonces;

    //the withdrawal credentials for which all ETH2 deposits should be pointed
    bytes32 public withdrawalCredentials;
    
    IDepositContract public depositContract;
    Repository public posMiddleware;
    mapping(bytes32 => mapping(address => bool)) public depositProven;
    IInvestmentManager public investmentManager;
    bytes32 public immutable consensusLayerDepositRoot;
    IProofOfStakingOracle public postOracle;
    
    constructor(bytes32 _consensusLayerDepositRoot) {
        consensusLayerDepositRoot = _consensusLayerDepositRoot;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(DOMAIN_TYPEHASH, bytes("EigenLayr"), block.chainid, address(this))
        );
    }
}