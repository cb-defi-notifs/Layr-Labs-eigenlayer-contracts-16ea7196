// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IQuorumRegistry.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../middleware/DataLayr/DataLayrChallengeUtils.sol";
import "../../libraries/DataStoreUtils.sol";

/**
 * @title Abstract contract that implements reuseable 'challenge' functionality for DataLayr.
 * @author Layr Labs, Inc.
 */
abstract contract DataLayrChallengeBase {
    using SafeERC20 for IERC20;

    // commitTime is marked as equal to 'CHALLENGE_UNSUCCESSFUL' in the event that a challenge provably fails
    uint256 public constant CHALLENGE_UNSUCCESSFUL = 1;
    // confirmAt is marked as equal to 'CHALLENGE_SUCCESSFUL' in the event that a challenge succeeds
    uint256 public constant CHALLENGE_SUCCESSFUL = type(uint256).max;
    // length of window during which the responses can be made to the challenge
    uint256 public immutable CHALLENGE_RESPONSE_WINDOW;
    // amount of token required to be placed as collateral when a challenge is opened
    uint256 public immutable COLLATERAL_AMOUNT;

    IQuorumRegistry public immutable dlRegistry;
    DataLayrChallengeUtils public immutable challengeUtils;
    IDataLayrServiceManager public immutable dataLayrServiceManager;

    constructor(
        IDataLayrServiceManager _dataLayrServiceManager,
        IQuorumRegistry _dlRegistry,
        DataLayrChallengeUtils _challengeUtils,
        uint256 _CHALLENGE_RESPONSE_WINDOW,
        uint256 _COLLATERAL_AMOUNT
    ) {
        dataLayrServiceManager = _dataLayrServiceManager;
        dlRegistry = _dlRegistry;
        challengeUtils = _challengeUtils;
        CHALLENGE_RESPONSE_WINDOW = _CHALLENGE_RESPONSE_WINDOW;
        COLLATERAL_AMOUNT = _COLLATERAL_AMOUNT;
    }

    function challengeSuccessful(bytes32 headerHash) public view virtual returns (bool);

    function challengeUnsuccessful(bytes32 headerHash) public view virtual returns (bool);

    function challengeExists(bytes32 headerHash) public view virtual returns (bool);

    function challengeClosed(bytes32 headerHash) public view virtual returns (bool);

    function _markChallengeSuccessful(bytes32 headerHash) internal virtual;

    function _recordChallengeDetails(bytes calldata header, bytes32 headerHash) internal virtual;

    function _challengeCreationEvent(bytes32 headerHash) internal virtual;

    function _returnChallengerCollateral(bytes32 headerHash) internal virtual;

    function openChallenge(bytes calldata header, IDataLayrServiceManager.DataStoreSearchData calldata searchData)
        external
    {
        // calculate headherHash from header

        {
            require(
                dataLayrServiceManager.getDataStoreHashesForDurationAtTimestamp(
                    searchData.duration, searchData.timestamp, searchData.index
                ) == DataStoreUtils.computeDataStoreHash(searchData.metadata),
                "DataLayrChallengeBase.openChallenge: Provided metadata does not match stored datastore metadata hash"
            );

            // check that disperser had acquire quorum for this dataStore
            require(searchData.metadata.signatoryRecordHash != bytes32(0), "Dump is not committed yet");

            // check that the dataStore is still ongoing
            uint256 expireTime = searchData.timestamp + searchData.duration;
            require(block.timestamp <= expireTime, "DataLayrChallengeBase.openChallenge: Dump has already expired");
        }

        bytes32 headerHash = searchData.metadata.headerHash;

        // check that the challenge doesn't exist yet
        require(!challengeExists(headerHash), "DataLayrChallengeBase.openChallenge: Challenge already opened for headerHash");

        _recordChallengeDetails(header, headerHash);

        // transfer 'COLLATERAL_AMOUNT' of IERC20 'collateralToken' to this contract from msg.sender, as collateral for the challenger
        dataLayrServiceManager.collateralToken().safeTransferFrom(msg.sender, address(this), COLLATERAL_AMOUNT);

        _challengeCreationEvent(headerHash);
    }

    /// @notice Mark a challenge as successful when it has succeeded. Operators can subsequently be slashed.
    function resolveChallenge(bytes32 headerHash) external {
        require(challengeExists(headerHash), "DataLayrChallengeBase.resolveChallenge: Challenge does not exist");
        require(!challengeUnsuccessful(headerHash), "DataLayrChallengeBase.resolveChallenge: Challenge failed");
        // check that the challenge window is no longer open
        require(challengeClosed(headerHash), "DataLayrChallengeBase.resolveChallenge: Challenge response period has not yet elapsed");

        // set challenge commit time equal to 'CHALLENGE_SUCCESSFUL', so the same challenge cannot be opened a second time,
        // and to signal that the challenge has been lost by the signers
        _markChallengeSuccessful(headerHash);

        // return challenger collateral
        _returnChallengerCollateral(headerHash);
    }

    // slash an operator who signed a headerHash but failed a subsequent challenge
    function slashOperator(
        bytes32 headerHash,
        address operator,
        uint256 nonSignerIndex,
        uint32 operatorHistoryIndex,
        IDataLayrServiceManager.DataStoreSearchData calldata searchData,
        IDataLayrServiceManager.SignatoryRecordMinusDataStoreId calldata signatoryRecord
    )
        public
    {
        // verify that the challenge has been lost by the operator side
        require(challengeSuccessful(headerHash), "DataLayrChallengeBase.slashOperator: Challenge not successful");

        require(
            dataLayrServiceManager.getDataStoreHashesForDurationAtTimestamp(
                searchData.duration, searchData.timestamp, searchData.index
            ) == DataStoreUtils.computeDataStoreHash(searchData.metadata),
            "DataLayrChallengeBase.slashOperator: Provided metadata does not match stored datastore metadata hash"
        );

       
         bytes32 signatoryRecordHash = keccak256(
                                            abi.encodePacked(
                                                searchData.metadata.globalDataStoreId, 
                                                signatoryRecord.nonSignerPubkeyHashes, 
                                                signatoryRecord.totalEthStakeSigned, 
                                                signatoryRecord.totalEigenStakeSigned
                                            )
                                        );

        require(
            searchData.metadata.signatoryRecordHash == signatoryRecordHash, 
            "DataLayrLowDegreeChallenge.lowDegreeChallenge: provided signatoryRecordHash does not match signatorRecordHash in provided searchData"
        );

        // verify that operator was active *at the blockNumber*
        bytes32 operatorPubkeyHash = dlRegistry.getOperatorPubkeyHash(operator);
        IQuorumRegistry.OperatorStake memory operatorStake =
            dlRegistry.getStakeFromPubkeyHashAndIndex(operatorPubkeyHash, operatorHistoryIndex);
        require(
            // operator must have become active/registered before (or at) the block number
            (operatorStake.updateBlockNumber <= searchData.metadata.blockNumber)
            // operator must have still been active after (or until) the block number
            // either there is a later update, past the specified blockNumber, or they are still active
            && (
                operatorStake.nextUpdateBlockNumber >= searchData.metadata.blockNumber
                    || operatorStake.nextUpdateBlockNumber == 0
            ),
            "DataLayrChallengeBase.slashOperator: operator was not active during blockNumber specified by dataStoreId / headerHash"
        );

        /**
         * @notice Check that the DataLayr operator who is getting slashed was
         * actually part of the quorum for the @param dataStoreId.
         *
         * The burden of responsibility lies with the challenger to show that the DataLayr operator
         * is not part of the non-signers for the DataStore. Towards that end, challenger provides
         * @param nonSignerIndex such that if the relationship among nonSignerPubkeyHashes (nspkh) is:
         * uint256(nspkh[0]) <uint256(nspkh[1]) < ...< uint256(nspkh[index])< uint256(nspkh[index+1]),...
         * then,
         * uint256(nspkh[index]) <  uint256(operatorPubkeyHash) < uint256(nspkh[index+1])
         */
        /**
         * @dev checkSignatures in DataLayrBLSSignatureChecker.sol enforces the invariant that hash of
         * non-signers pubkey is recorded in the compressed signatory record in an  ascending
         * manner.
         */

        {
            if (signatoryRecord.nonSignerPubkeyHashes.length != 0) {
                // check that operator was *not* in the non-signer set (i.e. they *did* sign)
                challengeUtils.checkExclusionFromNonSignerSet(operatorPubkeyHash, nonSignerIndex, signatoryRecord);
                
            }
        }

        dataLayrServiceManager.freezeOperator(operator);
    }
}
