// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IDelegationTerms.sol";
import "../libraries/SparseMerkle.sol";

/**
 * @title A 'Delegation Terms' contract that an operator can use to distribute earnings to stakers by posting Merkle roots
 * @author Layr Labs, Inc.
 * @notice This contract specifies the delegation terms of a given operator. When a staker delegates its stake to an operator,
 * it has to agrees to the terms set in the operator's 'Delegation Terms' contract. Payments to an operator are routed through
 * their specified 'Delegation Terms' contract for subsequent distribution of earnings to individual stakers.
 * There are also hooks that call into an operator's DelegationTerms contract when a staker delegates to or undelegates from
 * the operator.
 * @dev This contract uses a system in which the operator posts roots of a *sparse Merkle tree*. Each leaf of the tree is expected
 * to contain the **cumulative** earnings of a staker. This will reduce the total number of actions that stakers who claim only rarely
 * have to take, while allowing stakers to claim their earnings as often as new Merkle roots are posted.
 */
contract DelegationTerms_Merkle is SparseMerkle, Ownable, IDelegationTerms {
    using SafeERC20 for IERC20;

    // spare Merkle tree functionality

    // staker => token => cumulative amount *claimed*
    mapping(address => mapping(IERC20 => uint256)) public cumulativeClaimedByStakerOfToken;

    // history of Merkle roots
    bytes32[] public merkleRoots;

    event NewMerkleRootPosted(bytes32 newRoot);

    constructor(uint256 _TREE_DEPTH)
        SparseMerkle(_TREE_DEPTH)
    {}

    /**
     * @notice Used by the operator to withdraw tokens directly from this contract.
     * @param tokens ERC20 tokens to withdraw.
     * @param amounts The amount of each respective ERC20 token to withdraw.
     */ 
    function operatorWithdrawal(IERC20[] calldata tokens, uint256[] calldata amounts) external onlyOwner {
        uint256 tokensLength = tokens.length;
        for (uint256 i; i < tokensLength;) {
            tokens[i].safeTransfer(msg.sender, amounts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Used by the operator to post an updated root of the stakers' all-time earnings
    function postMerkleRoot(bytes32 newRoot) external onlyOwner {
        merkleRoots.push(newRoot);
        emit NewMerkleRootPosted(newRoot);
    }

    function proveEarningsAndWithdraw(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes32[] calldata proofElements,
        uint256 nodeWrittenBitmap,
        uint256 nodeIndex,
        uint256 rootIndex
    ) external {
        // calculate the leaf that the `msg.sender` is claiming
        bytes32 leafHash = calculateLeafHash(msg.sender, tokens, amounts);

        // check inclusion of the leafHash in the tree corresponding to `merkleRoots[rootIndex]`
        require(
            checkInclusion(
                proofElements,
                nodeWrittenBitmap,
                nodeIndex,
                leafHash,
                merkleRoots[rootIndex]
            ),
            "proof of inclusion failed"
        );

        uint256 tokensLength = tokens.length;
        for (uint256 i; i < tokensLength;) {
            // read previously claimed amount in storage
            uint256 alreadyClaimed = cumulativeClaimedByStakerOfToken[msg.sender][tokens[i]];

            // calculate amount to send
            uint256 amountToSend = amounts[i] - alreadyClaimed;

            if (amountToSend != 0) {
                // update claimed amount in storage
                cumulativeClaimedByStakerOfToken[msg.sender][tokens[i]] = amounts[i];

                // actually send the tokens
                tokens[i].safeTransfer(msg.sender, amounts[i]);
            }
            unchecked {
                ++i;
            }
        }
    }

    function calculateLeafHash(address staker, IERC20[] memory tokens, uint256[] memory amounts) internal pure returns (bytes32) {
        return keccak256(abi.encode(staker, tokens, amounts));
    }

    // FUNCTIONS FROM INTERFACE
    function payForService(IERC20, uint256) external payable {
    }

    /**
     * @notice Hook for receiving new delegation   
     */
    function onDelegationReceived(
        address,
        IInvestmentStrategy[] memory,
        uint256[] memory
    ) external pure {
    }

    /**
     * @notice Hook for withdrawing delegation   
     */
    function onDelegationWithdrawn(
        address,
        IInvestmentStrategy[] memory,
        uint256[] memory
    ) external pure {
    }
}