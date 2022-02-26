// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/IDepositContract.sol";
import "../interfaces/CoreInterfaces.sol";
import "../interfaces/InvestmentInterfaces.sol";
import "./BLS.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// todo: slashing functionality
// todo: figure out token moving
// todo: figure out deposit trie and proof of staking signature
contract EigenLayrDeposit is IEigenLayrDeposit {
    bytes32 public withdrawalCredentials;
    bytes32 public immutable consensusLayerDepositRoot;
    bytes32 public constant legacyDepositPermissionMessage = 0x656967656e4c61797252657374616b696e67596f754b6e6f7749744261626179;
    IDepositContract public depositContract;
    mapping(IERC20 => bool) public isAllowedLiquidStakedToken;
    mapping(address => bool) public legacyDepositProven;
    uint256 constant DEPOSIT_CONTRACT_TREE_DEPTH = 32;
    bytes32[DEPOSIT_CONTRACT_TREE_DEPTH] zero_hashes;
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
        // Compute hashes in empty sparse Merkle tree
        for (
            uint256 height = 0;
            height < DEPOSIT_CONTRACT_TREE_DEPTH - 1;
            height++
        )
            zero_hashes[height + 1] = sha256(
                abi.encodePacked(zero_hashes[height], zero_hashes[height])
            );

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
        require(!legacyDepositProven[depositer], "Depositer has already proven their stake");
        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, legacyDepositPermissionMessage));
        require(ECDSA.recover(messageHash, signature) == depositer, "Invalid signature");
        bytes32 leaf = keccak256(abi.encodePacked(depositer, amount));
        require(MerkleProof.verify(proof, consensusLayerDepositRoot, leaf), "Invalid merkle proof");
        legacyDepositProven[depositer] = true;
        // mark deposited eth in investment contract
        investmentManager.depositConsenusLayerEth(depositer, msg.value);
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

    // proves the a deposit with given parameters is present in the consensus layer
    function proveConsensusLayerDeposit(
        bytes32[] calldata treeProof,
        bool[] calldata flags,
        uint256 numBranchFlags,
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata signature,
        uint64 stake
    ) internal pure {
        bytes32 node = treeProof[0];
        //     require(
        //         sha256(
        //             abi.encodePacked(
        //                 node,
        //                 depositContract.get_deposit_count(),
        //                 bytes24(0)
        //             )
        //         ) == depositContract.get_deposit_root(),
        //         "Deposit root different from proof"
        //     );

        //     // run root contruction backward till we get the branch we want
        //     uint256 treeProofIndex = 1;
        //     uint256 index = 0;
        //     while (index < numBranchFlags) {
        //         if (flags[index]) {
        //             require(
        //                 node ==
        //                     sha256(
        //                         abi.encodePacked(
        //                             treeProof[treeProofIndex], //branch
        //                             treeProof[treeProofIndex + 1] // prev node
        //                         )
        //                     ),
        //                 "Branch or node preimage provided are incorrect"
        //             );
        //             node = treeProof[treeProofIndex + 1];
        //             treeProofIndex += 2;
        //         } else {
        //             require(
        //                 node ==
        //                     sha256(
        //                         abi.encodePacked(
        //                             treeProof[treeProofIndex], //prev node
        //                             zero_hashes[
        //                                 DEPOSIT_CONTRACT_TREE_DEPTH - index - 1
        //                             ] // zero level
        //                         )
        //                     ),
        //                 "Node preimage provided is incorrect"
        //             );
        //             node = treeProof[treeProofIndex];
        //             treeProofIndex += 1;
        //         }
        //         index++;
        //     }

        //     // "binary hash search" the deposit root in question out of the branch
        //     node = treeProof[treeProofIndex - 1]; // get the branch from the last step of the proof (make sure that last step is branch step?)
        //     while (index < flags.length) {
        //         require(
        //             node ==
        //                 sha256(
        //                     abi.encodePacked(
        //                         treeProof[treeProofIndex],
        //                         treeProof[treeProofIndex + 1]
        //                     )
        //                 ),
        //             "Hash of branches is incorrect"
        //         );
        //         if (flags[index]) {
        //             node = treeProof[treeProofIndex];
        //         } else {
        //             node = treeProof[treeProofIndex + 1];
        //         }
        //         treeProofIndex += 2;
        //     }

        //     // check that proven node is hashed data
        //     require(
        //         node ==
        //             sha256(
        //                 abi.encodePacked(
        //                     sha256(
        //                         abi.encodePacked(
        //                             sha256(abi.encodePacked(pubkey, bytes16(0))),
        //                             withdrawal_credentials
        //                         )
        //                     ),
        //                     sha256(
        //                         abi.encodePacked(
        //                             to_little_endian_64(stake),
        //                             bytes24(0),
        //                             sha256(
        //                                 abi.encodePacked(
        //                                     sha256(
        //                                         abi.encodePacked(signature[:64])
        //                                     ),
        //                                     sha256(
        //                                         abi.encodePacked(
        //                                             signature[64:],
        //                                             bytes32(0)
        //                                         )
        //                                     )
        //                                 )
        //                             )
        //                         )
        //                     )
        //                 )
        //             )
        //     );
        //     // jeffC, they are pointing to a deposit of "stake" amount in Consensus Layer, with the passed pubkey, withdrawal credentials, and signature
    }

    function depositPOSProof(
        bytes32[] calldata treeProof,
        bool[] calldata flags,
        uint256 numBranchFlags,
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata signature,
        uint64 stake
    ) external {
        // check that the specified deposit exists in the deposit tree
        proveConsensusLayerDeposit(
            treeProof,
            flags,
            numBranchFlags,
            pubkey,
            withdrawal_credentials,
            signature,
            stake
        );
        // the deposit exists!, the call will revert otherwise
        // mark deposited eth in investment contract
        investmentManager.depositConsenusLayerEth(msg.sender, stake);
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
