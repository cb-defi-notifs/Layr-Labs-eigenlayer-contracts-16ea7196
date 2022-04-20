// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Eigen.sol";
import "../interfaces/IDepositContract.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IEigenLayrDeposit.sol";
import "../interfaces/ProofOfStakingInterfaces.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../utils/Initializable.sol";
import "./EigenLayrDepositStorage.sol";

/* TODO:
Currently, in the EigenLayrDeposit contract, all three function depositEthIntoConsensusLayer ,  proveLegacyConsensusLayerDeposit , and depositPOSProof call the same function on the InvestmentManager contract — depositConsenusLayerEth .
However, the function depositEthIntoConsensusLayer  works differently, since in this case, the withdrawal credentials are set to the address of the EigenLayrDeposit contract itself (i.e. the withdrawal credentials are controlled by EigenLayr itself)
@Gautham Anant I believe we should have some either additional or separate logic for this function, since it seems fundamentally different (funds are inherently slashable by us, vs. not slashable at all).
Let’s discuss a good resolution for this
*/
// todo: slashing functionality
// todo: figure out token moving
/**
 * @notice This is the contract for any user to deposit their stake into EigenLayr in order
 *         to participate in providing validation servies to middlewares. The main
 *         functionalities of this contract are:
 *           - enabling deposit of staking derivatives from liquid staking into EigenLayr while
 *             describing which investment strategy to use for investing these staking derivatives,
 *           - enabling proving staking of ETH into settlement layer (beacon chain)
 *             before the launch of EigenLayr and then account it for staking into EigenLayr,
 *           - enabling depositing ETH into settlement layer via EigenLayr's withdrawal
 *             certificate and then then account it for staking into EigenLayr,
 *           - enabling acceptance of proof of staking into settlement layer, via depositor's
 *             own withdrawal certificate, in order to use it for staking into EigenLayr.
 */
contract EigenLayrDeposit is
    Initializable,
    EigenLayrDepositStorage,
    IEigenLayrDeposit
{
    bytes32 public immutable consensusLayerDepositRoot;
    IProofOfStakingOracle postOracle;

    constructor(bytes32 _consensusLayerDepositRoot) {
        consensusLayerDepositRoot = _consensusLayerDepositRoot;
    }

    function initialize(
        IDepositContract _depositContract,
        IInvestmentManager _investmentManager,
        IProofOfStakingOracle _postOracle
    ) external initializer {
        withdrawalCredentials =
            (bytes32(uint256(1)) << 62) |
            bytes32(bytes20(address(this))); //0x010000000000000000000000THISCONTRACTADDRESSHEREFORTHELAST20BYTES
        depositContract = _depositContract;
        investmentManager = _investmentManager;
        postOracle = _postOracle;
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

    /**
     *   @notice It is used to prove staking of ETH into settlement layer (beacon chain)
     *           before the launch of EigenLayr. We call this
     *           as legacy consensus layer deposit. EigenLayr now
     *           counts this staked ETH, under re-staking paradigm, as being
     *           staked in EigenLayr.
     */
    /** @dev The snapshot of which depositor has staked what amount of ETH into settlement layer
     *        (beacon chain) is captured using a merkle tree where the leaf node is given by
     *        keccak256(abi.encodePacked(depositor, amount)). This merkle tree is then used
     *        to prove depositor's stake in the settlement layer.
     */
    /// @param proof is the merkle proof in the above merkle tree.
    /// @param signature is the signature on the message "keccak256(abi.encodePacked(msg.sender, legacyDepositPermissionMessage)"
    // CRITIC - change the name to "proveLegacySettlementLayerDeposit"
    function proveLegacyConsensusLayerDeposit(
        bytes32[] calldata proof,
        address depositor,
        bytes calldata signature,
        uint256 amount
    ) external payable {
        require(
            !depositProven[consensusLayerDepositRoot][depositor],
            "Depositer has already proven their stake"
        );
        if (depositor == address(0)) {
            depositor = msg.sender;
        } else {
            bytes32 messageHash = keccak256(
                abi.encodePacked(msg.sender, legacyDepositPermissionMessage)
            );

            // recovering the address to whom the signature belongs to and verifying it
            // is that of the depositor.
            require(
                ECDSA.recover(messageHash, signature) == depositor,
                "Invalid signature"
            );
        }
        
        bytes32 leaf = keccak256(abi.encodePacked(depositor, amount));

        // verifying the merkle proof
        require(
            MerkleProof.verify(proof, consensusLayerDepositRoot, leaf),
            "Invalid merkle proof"
        );

        // record that depositor has successfully proven its stake into legacy consensus layer
        depositProven[consensusLayerDepositRoot][depositor] = true;

        // mark deposited ETH in investment contract
        investmentManager.depositConsenusLayerEth(depositor, amount);
    }

    /**
     *    @notice Used for letting EigenLayr know that depositor's ETH should
     *            be staked in settlement layer via EigenLayr's withdrawal certificate
     *            and then be re-staked in EigenLayr.
     */
    function depositEthIntoConsensusLayer(
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external payable {
        //deposit eth into consensus layer using EigenLayr's withdrawal certificate
        depositContract.deposit{value: msg.value}(
            pubkey,
            abi.encodePacked(withdrawalCredentials),
            signature,
            depositDataRoot
        );

        // mark deposited eth in investment contract
        investmentManager.depositConsenusLayerEth(msg.sender, msg.value);
    }

    /**
     *   @notice Used to prove new staking of ETH into settlement layer (beacon chain)
     *           after the launch of EigenLayr (staking in settlement layer was done
     *           by using depositor's own withdrawal certificate) and then re-stake it in
     *           EigenLayr.
     */
    /**
     *   @dev In order to update the snapshot of depositor and their stake in settlement
     *        layer, an EigenLayr query is made on the most recent commitment of the snapshot.
     *        The new depositor's in the settlement layer who want to participate in
     *        EigenLayr has to prove their stake against this commitment.
     */
    function depositPOSProof(
        uint256 blockNumber,
        bytes32[] calldata proof,
        address depositor,
        bytes calldata signature,
        uint256 amount
    ) external {
        // get the most recent commitment of trie in settlement layer (beacon chain) that
        // describes the which depositor staked how much ETH.
        bytes32 depositRoot = postOracle.getDepositRoot(blockNumber);

        require(
            !depositProven[depositRoot][depositor],
            "Depositer has already proven their stake"
        );
        bytes32 messageHash = keccak256(
            abi.encodePacked(msg.sender, legacyDepositPermissionMessage)
        );
        require(
            ECDSA.recover(messageHash, signature) == depositor,
            "Invalid signature"
        );
        bytes32 leaf = keccak256(abi.encodePacked(depositor, amount));
        require(
            MerkleProof.verify(proof, depositRoot, leaf),
            "Invalid merkle proof"
        );
        depositProven[depositRoot][depositor] = true;

        // mark deposited eth in investment contract
        investmentManager.depositConsenusLayerEth(depositor, amount);
    }
}
