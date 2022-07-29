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

    /// @notice The EIP-712 typehash for the deposit claim struct used by the contract
    bytes32 public constant DEPOSIT_CLAIM_TYPEHASH = keccak256("DepositClaim(address claimer)");
    
    /// @notice EIP-712 Domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    // Merkle root for tree of beacon chain deposits at deployment of this contract
    bytes32 public immutable consensusLayerDepositRoot;

    // "ETH2" deposit contract
    IDepositContract public immutable depositContract;

    //the withdrawal credentials for which all ETH2 deposits should be pointed
    bytes32 public withdrawalCredentials;
    
    // middleware that provides updates containing all the new beacon chain deposits
    IProofOfStakingOracle public postOracle;

    // EigenLayr InvestmentManager contract
    IInvestmentManager public investmentManager;

    // delegator => number of signed nonce (used in delegateToBySignature and proveLegacyConsensusLayerDepositBySignature)
    mapping(address => uint256) nonces;

    // consensusLayerDepositRoot => depositor => whether they have proven their deposit or not
    mapping(bytes32 => mapping(address => bool)) public depositProven;
    
    constructor(bytes32 _consensusLayerDepositRoot, IDepositContract _depositContract) {
        consensusLayerDepositRoot = _consensusLayerDepositRoot;
        depositContract = _depositContract;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(DOMAIN_TYPEHASH, bytes("EigenLayr"), block.chainid, address(this))
        );
    }
}