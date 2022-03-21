// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "./Eigen.sol";
import "../interfaces/IDepositContract.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IEigenLayrDeposit.sol";
import "../middleware/QueryManager.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../utils/Initializable.sol";
import "./storage/EigenLayrDepositStorage.sol";

// todo: slashing functionality
// todo: figure out token moving
contract EigenLayrDeposit is Initializable, EigenLayrDepositStorage, IEigenLayrDeposit {
    bytes32 public immutable consensusLayerDepositRoot;
    Eigen public immutable eigen;

    constructor(
        bytes32 _consensusLayerDepositRoot,
        Eigen _eigen
    ) {
        consensusLayerDepositRoot = _consensusLayerDepositRoot;
        eigen = _eigen;
    }

    function initialize (
        IDepositContract _depositContract,
        IInvestmentManager _investmentManager
    ) initializer external {
        withdrawalCredentials =
            (bytes32(uint256(1)) << 62) |
            bytes32(bytes20(address(this))); //0x010000000000000000000000THISCONTRACTADDRESSHEREFORTHELAST20BYTES
        depositContract = _depositContract;
        investmentManager = _investmentManager;
    }

    /**
      * @notice converts the deposited ETH into the specified liquidStakeToken which is 
      * then invested into some specified strategy 
    */
    /// @param liquidStakeToken specifies the preference for liquid staking,
    /// @param strategy specifies the strategy in which the above liquidStakeToken is to be invested in.  
    function depositETHIntoLiquidStaking(
        IERC20 liquidStakeToken,
        IInvestmentStrategy strategy
    ) external payable {
        require(
            isAllowedLiquidStakedToken[liquidStakeToken],
            "This liquid staking token is not permitted in EigenLayr"
        );

        // balance of liquidStakeToken before deposit
        uint256 depositAmount = liquidStakeToken.balanceOf(address(this)); 

        // send the ETH deposited to the ERC20 contract for liquidStakeToken
        // this liquidStakeToken is credited to EigenLayrDeposit contract (address(this))
        Address.sendValue(payable(address(liquidStakeToken)), msg.value);

        // increment in balance of liquidStakeToken
        depositAmount =
            liquidStakeToken.balanceOf(address(this)) -
            depositAmount; 
        
        // approve investmentManager contract to be able to take out liquidStakeToken
        liquidStakeToken.approve(address(investmentManager), depositAmount);

        
        investmentManager.depositIntoStrategy(
            msg.sender,
            strategy,
            liquidStakeToken,
            depositAmount
        );
    }


    // proves deposit against legacy deposit root
    /** 
    *   @notice    
    */
    function proveLegacyConsensusLayerDeposit(
        bytes32[] calldata proof,
        address depositer,
        bytes calldata signature,
        uint256 amount
    ) external payable {
        require(
            !depositProven[consensusLayerDepositRoot][depositer],
            "Depositer has already proven their stake"
        );
        bytes32 messageHash = keccak256(
            abi.encodePacked(msg.sender, legacyDepositPermissionMessage)
        );
        require(
            ECDSA.recover(messageHash, signature) == depositer,
            "Invalid signature"
        );
        bytes32 leaf = keccak256(abi.encodePacked(depositer, amount));
        require(
            MerkleProof.verify(proof, consensusLayerDepositRoot, leaf),
            "Invalid merkle proof"
        );
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

    function depositEigen(uint256 amount) external payable {
        eigen.safeTransferFrom(
            msg.sender,
            address(investmentManager),
            eigenTokenId,
            amount,
            "0x"
        );

        // mark deposited eigen in investment contract
        investmentManager.depositEigen(msg.sender, msg.value);
    }

    function depositPOSProof(
        bytes32 queryHash,
        bytes32[] calldata proof,
        address depositer,
        bytes calldata signature,
        uint256 amount
    ) external {
        bytes32 depositRoot = posMiddleware.getQueryOutcome(queryHash);
        require(
            !depositProven[depositRoot][depositer],
            "Depositer has already proven their stake"
        );
        bytes32 messageHash = keccak256(
            abi.encodePacked(msg.sender, legacyDepositPermissionMessage)
        );
        require(
            ECDSA.recover(messageHash, signature) == depositer,
            "Invalid signature"
        );
        bytes32 leaf = keccak256(abi.encodePacked(depositer, amount));
        require(
            MerkleProof.verify(proof, consensusLayerDepositRoot, leaf),
            "Invalid merkle proof"
        );
        depositProven[depositRoot][depositer] = true;
        // mark deposited eth in investment contract
        investmentManager.depositConsenusLayerEth(depositer, amount);
    }
}
