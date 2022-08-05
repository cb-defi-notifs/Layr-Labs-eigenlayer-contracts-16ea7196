// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IEigenLayrDeposit.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "./EigenLayrDepositStorage.sol";

// import "ds-test/test.sol";

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
    // ,DSTest
{
    constructor(bytes32 _consensusLayerDepositRoot)
        EigenLayrDepositStorage(_consensusLayerDepositRoot)
    {
        // TODO: uncomment for production use!
        //_disableInitializers();
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
        // balance of liquidStakeToken before deposit
        uint256 lstBalanceBefore = liquidStakeToken.balanceOf(address(this));

        // send the ETH deposited to the ERC20 contract for liquidStakeToken
        // this liquidStakeToken is credited to EigenLayrDeposit contract (address(this))
        Address.sendValue(payable(address(liquidStakeToken)), msg.value);

        // increment in balance of liquidStakeToken
        uint256 depositAmount = liquidStakeToken.balanceOf(address(this)) -
            lstBalanceBefore;

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
     *   @notice It is used to prove staking of ETH into beacon chain
     *           before the launch of EigenLayer. We call this
     *           as legacy consensus layer deposit. EigenLayr now
     *           counts this staked ETH, under re-staking paradigm, as being
     *           staked in EigenLayer.
     */
    /** @dev The snapshot of which depositor has staked what amount of ETH into 
     *        beacon chain is captured using a merkle tree where the leaf node is given by
     *        keccak256(abi.encodePacked(depositor, amount)). This merkle tree is then used
     *        to prove depositor's stake in the settlement layer.
     */
    /// @param proof is the merkle proof in the above merkle tree.
    /// CRITIC--- change name to proveBeaconChainDeposit?
    function proveLegacyConsensusLayerDeposit(
        bytes32[] calldata proof,
        uint256 amount
    ) external {
        _proveLegacyConsensusLayerDeposit(
            msg.sender,
            msg.sender,
            proof,
            amount
        );
    }


    /**
     @notice This is called by parties that have a signature approving
     the deposit claim from consensus layer depositors themselves
     to claim their consensus layer ETH on eigenlayer
     */
    function proveLegacyConsensusLayerDepositBySignature(
            address depositor,
            bytes32 r,
            bytes32 vs,
            uint256 expiry, 
            uint256 nonce,
            bytes32[] calldata proof,
            uint256 amount
    ) public {
        require(nonces[depositor] == nonce, "invalid delegation nonce");

        require(
            expiry == 0 || expiry <= block.timestamp,
            "delegation signature expired"
        );

        bytes32 structHash = keccak256(
            abi.encode(DEPOSIT_CLAIM_TYPEHASH, msg.sender)
        );

        bytes32 digestHash = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );

        // Recovering the address of the signer from the signature.
        // This signer is the supposed depositer.
        address recoveredAddress = ECDSA.recover(
            digestHash,
            r,
            vs
        );

        require(
            recoveredAddress != address(0),
            "delegateToBySignature: bad signature"
        );

        require(
            recoveredAddress == depositor,
            "delegateToBySignature: sig not from depositor"
        );


        // increment delegator's delegationNonce
        ++nonces[depositor];

        _proveLegacyConsensusLayerDeposit(
            depositor,
            msg.sender,
            proof,
            amount
        );
    }



    /**
     * @notice It is used to prove staking of ETH into settlement layer (beacon chain)
     *           before the launch of EigenLayr. We call this
     *           as legacy consensus layer deposit. EigenLayr now
     *           counts this staked ETH, under re-staking paradigm, as being
     *           staked in EigenLayer.
     */
    /** @dev The snapshot of which depositor has staked what amount of ETH into settlement layer
     *        (beacon chain) is captured using a merkle tree where the leaf node is given by
     *        keccak256(abi.encodePacked(depositor, amount)). This merkle tree is then used
     *        to prove depositor's stake in the settlement layer.
     */
    /// @param proof is the merkle proof in the above merkle tree.
    // CRITIC - change the name to "proveLegacySettlementLayerDeposit"
    function _proveLegacyConsensusLayerDeposit(
        address depositor,
        address onBehalfOf,
        bytes32[] calldata proof,
        uint256 amount
    ) internal {
        require(
            !depositProven[consensusLayerDepositRoot][depositor],
            "Depositer has already proven their stake"
        );

        bytes32 leaf = keccak256(abi.encodePacked(depositor, amount));

        // verifying the merkle proof
        // TODO: This will likely be changed from a hardcoded root to an oracle service on EigenLayer
        require(
            MerkleProof.verify(proof, consensusLayerDepositRoot, leaf),
            "Invalid merkle proof"
        );

        // record that depositor has successfully proven its stake into legacy consensus layer
        depositProven[consensusLayerDepositRoot][depositor] = true;

        // mark deposited ETH in investment contract
        investmentManager.depositProofOfStakingEth(onBehalfOf, amount);
    }




    /**
     *    @notice Used for letting EigenLayer know that depositor's ETH should
     *            be staked in settlement layer via EigenLayr's withdrawal certificate
     *            and then be re-staked in EigenLayr.
     */
    // TODO: MAKE DEPOSITS INTO CLE LIKE POS PROOFS DUE TO LACK OF PRECOMPILE SUPPORT
    // THIS FUNCTION IS BROKEN, DO NOT LOOK AT IT YET
    // We will likely use the SNARK being developed by 0xPARC + fraud proofs decribed in 
    // https://research.lido.fi/t/optimistic-oracle-fraud-proofs-to-mitigate-consensus-layer-deposit-frontrunning/2452/7
    // to secure against attacks such as https://research.lido.fi/t/mitigations-for-deposit-front-running-vulnerability/1239
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
    // TODO: Integrate this with consensus layer oracle eventually
    // function depositPOSProof(
    //     uint256 blockNumber,
    //     bytes32[] calldata proof,
    //     address depositor,
    //     bytes calldata signature,
    //     uint256 amount
    // ) external {
    //     // get the most recent commitment of trie in settlement layer (beacon chain) that
    //     // describes the which depositor staked how much ETH.
    //     bytes32 depositRoot = postOracle.getDepositRoot(blockNumber);

    //     require(
    //         !depositProven[depositRoot][depositor],
    //         "Depositer has already proven their stake"
    //     );
    //     bytes32 messageHash = keccak256(
    //         abi.encodePacked(msg.sender, legacyDepositPermissionMessage)
    //     );
    //     require(
    //         ECDSA.recover(messageHash, signature) == depositor,
    //         "Invalid signature"
    //     );
    //     bytes32 leaf = keccak256(abi.encodePacked(depositor, amount));
    //     require(
    //         MerkleProof.verify(proof, depositRoot, leaf),
    //         "Invalid merkle proof"
    //     );
    //     depositProven[depositRoot][depositor] = true;

    //     // TODO: @Gautham should this credit to a specified address? right now it necesarily goes to 'depositor'
    //     //      -- was the intention for it to go to msg.sender?
    //     // mark deposited eth in investment contract
    //     investmentManager.depositProofOfStakingEth(depositor, amount);
    // }
}
