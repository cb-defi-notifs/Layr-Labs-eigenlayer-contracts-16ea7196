// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/IDepositContract.sol";
import "../interfaces/CoreInterfaces.sol";
import "../interfaces/InvestmentInterfaces.sol";
import "../middleware/QueryManager.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// todo: slashing functionality
// todo: figure out token moving
contract EigenLayrDeposit is IEigenLayrDeposit {
    bytes32 public withdrawalCredentials;
    bytes32 public immutable consensusLayerDepositRoot;
    bytes32 public constant legacyDepositPermissionMessage = 0x656967656e4c61797252657374616b696e67596f754b6e6f7749744261626179;
    IDepositContract public depositContract;
    QueryManager public posMiddleware;
    mapping(IERC20 => bool) public isAllowedLiquidStakedToken;
    mapping(bytes32 => mapping(address => bool)) public depositProven;
    IInvestmentManager public investmentManager;

    constructor(
        IDepositContract _depositContract,
        IInvestmentManager _investmentManager,
        bytes32 _consensusLayerDepositRoot
    ) {
        withdrawalCredentials =
            (bytes32(uint256(1)) << 62) |
            bytes32(bytes20(address(this))); //0x010000000000000000000000THISCONTRACTADDRESSHEREFORTHELAST20BYTES
        depositContract = _depositContract;
        investmentManager = _investmentManager;
        consensusLayerDepositRoot = _consensusLayerDepositRoot;
    }

    // deposits eth into liquid staking and deposit stETH into strategy
    function depositETHIntoLiquidStaking(
        IERC20 liquidStakeToken,
        IInvestmentStrategy strategy
    ) external payable {
        require(
            isAllowedLiquidStakedToken[liquidStakeToken],
            "Liquid staking token is not allowed"
        );
        uint256 depositAmount = liquidStakeToken.balanceOf(address(this)); // stETH balance before deposit
        Address.sendValue(payable(address(liquidStakeToken)), msg.value);
        depositAmount =
            liquidStakeToken.balanceOf(address(this)) -
            depositAmount; // increment in stETH balance
        liquidStakeToken.approve(address(investmentManager), depositAmount);
        investmentManager.depositIntoStrategy(
            msg.sender,
            strategy,
            liquidStakeToken,
            depositAmount
        );
    }

    // proves deposit against legacy deposit root
    function proveLegacyConsensusLayerDeposit(
        bytes32[] calldata proof,
        address depositer,
        bytes calldata signature,
        uint256 amount
    ) external payable {
        require(!depositProven[consensusLayerDepositRoot][depositer], "Depositer has already proven their stake");
        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, legacyDepositPermissionMessage));
        require(ECDSA.recover(messageHash, signature) == depositer, "Invalid signature");
        bytes32 leaf = keccak256(abi.encodePacked(depositer, amount));
        require(MerkleProof.verify(proof, consensusLayerDepositRoot, leaf), "Invalid merkle proof");
        depositProven[consensusLayerDepositRoot][depositer] = true;
        // mark deposited eth in investment contract
        investmentManager.depositConsenusLayerEth(depositer, amount);
    }

    function depositEthIntoConsensusLayer(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable {
        //deposit eth into consensus layer
        depositContract.deposit{value: msg.value}(
            pubkey,
            abi.encodePacked(withdrawalCredentials),
            signature,
            depositDataRoot
        );

        // mark deposited eth in investment contract
        investmentManager.depositConsenusLayerEth(msg.sender, msg.value);
    }

    function depositPOSProof(
        bytes32 queryHash,
        bytes32[] calldata proof,
        address depositer,
        bytes calldata signature,
        uint256 amount
    ) external {
        bytes32 depositRoot = posMiddleware.getQueryOutcome(queryHash);
        require(!depositProven[depositRoot][depositer], "Depositer has already proven their stake");
        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, legacyDepositPermissionMessage));
        require(ECDSA.recover(messageHash, signature) == depositer, "Invalid signature");
        bytes32 leaf = keccak256(abi.encodePacked(depositer, amount));
        require(MerkleProof.verify(proof, consensusLayerDepositRoot, leaf), "Invalid merkle proof");
        depositProven[depositRoot][depositer] = true;
        // mark deposited eth in investment contract
        investmentManager.depositConsenusLayerEth(depositer, amount);
    }

    function to_little_endian_64(uint64 value)
        internal
        pure
        returns (bytes memory ret)
    {
        ret = new bytes(8);
        bytes8 bytesValue = bytes8(value);
        // Byteswapping during copying to bytes.
        ret[0] = bytesValue[7];
        ret[1] = bytesValue[6];
        ret[2] = bytesValue[5];
        ret[3] = bytesValue[4];
        ret[4] = bytesValue[3];
        ret[5] = bytesValue[2];
        ret[6] = bytesValue[1];
        ret[7] = bytesValue[0];
    }
}
