// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrRegistry.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../middleware/DataLayr/DataLayrChallengeUtils.sol";

abstract contract DataLayrChallengeBase {

     // commitTime is marked as equal to 'CHALLENGE_UNSUCCESSFUL' in the event that a challenge provably fails
    uint256 public constant CHALLENGE_UNSUCCESSFUL = 1;
    // commitTime is marked as equal to 'CHALLENGE_SUCCESSFUL' in the event that a challenge succeeds
    uint256 public constant CHALLENGE_SUCCESSFUL = type(uint256).max;
    // length of window during which the responses can be made to the challenge
    uint256 public immutable CHALLENGE_RESPONSE_WINDOW;
    // amount of token required to be placed as collateral when a challenge is opened
   	uint256 public immutable COLLATERAL_AMOUNT;

    IDataLayr public immutable dataLayr;
    IDataLayrRegistry public immutable dlRegistry;
    DataLayrChallengeUtils public immutable challengeUtils;
    IDataLayrServiceManager public immutable dataLayrServiceManager;

    constructor(
        IDataLayrServiceManager _dataLayrServiceManager,
        IDataLayr _dataLayr,
        IDataLayrRegistry _dlRegistry,
        DataLayrChallengeUtils _challengeUtils,
        uint256 _CHALLENGE_RESPONSE_WINDOW,
        uint256 _COLLATERAL_AMOUNT
    ) {
        dataLayrServiceManager = _dataLayrServiceManager;
        dataLayr = _dataLayr;
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

    function openChallenge(bytes calldata header) external {
        // calculate headherHash from header
        bytes32 headerHash = keccak256(header);

        {
            /**
            Get information on the dataStore for which disperser is being challenged. This dataStore was 
            constructed during call to initDataStore in DataLayr.sol by the disperser.
            */
            (
                uint32 dataStoreId,
                uint32 initTime,
                uint32 storePeriodLength,
                // uint32 blockNumber,
            ) = dataLayr.dataStores(headerHash);

            uint256 expireTime = initTime + storePeriodLength;

            // check that disperser had acquire quorum for this dataStore 
            require(dataLayrServiceManager.getDataStoreIdSignatureHash(dataStoreId) != bytes32(0), "Data store not committed");

            // check that the dataStore is still ongoing
            require(block.timestamp <= expireTime, "Dump has already expired");
        }

        // check that the challenge doesn't exist yet
        require(
            !challengeExists(headerHash),
            "Challenge already opened for headerHash"
        );

        _recordChallengeDetails(header, headerHash);

        // transfer 'COLLATERAL_AMOUNT' of IERC20 'collateralToken' to this contract from msg.sender, as collateral for the challenger 
        IERC20 collateralToken = dataLayrServiceManager.collateralToken();
        require(
            collateralToken.transferFrom(msg.sender, address(this), COLLATERAL_AMOUNT),
            "collateral must be transferred when initiating challenge"
        );

        _challengeCreationEvent(headerHash);
    }

    // mark a challenge as successful when it has succeeded. Operators can subsequently be slashed.
    function resolveChallenge(bytes32 headerHash) public {
        require(
            challengeExists(headerHash),
            "Challenge does not exist"
        );
        require(
            !challengeUnsuccessful(headerHash),
            "Challenge failed"
        );
        // check that the challenge window is no longer open
        require(
            challengeClosed(headerHash),
            "Challenge response period has not yet elapsed"
        );

	    // set challenge commit time equal to 'CHALLENGE_SUCCESSFUL', so the same challenge cannot be opened a second time,
    	// and to signal that the challenge has been lost by the signers
    	_markChallengeSuccessful(headerHash);
    }

    // slash an operator who signed a headerHash but failed a subsequent challenge
    function slashOperator(
        bytes32 headerHash,
        address operator,
        uint256 nonSignerIndex,
        uint32 operatorHistoryIndex,
        IDataLayrServiceManager.SignatoryRecordMinusDataStoreId calldata signatoryRecord
    ) external {
        // verify that the challenge has been lost by the operator side
    	require(challengeSuccessful(headerHash), "Challenge not successful");

        /**
        Get information on the dataStore for which disperser is being challenged. This dataStore was 
        constructed during call to initDataStore in DataLayr.sol by the disperser.
        */
        (
            uint32 dataStoreId,
            /*uint32 initTime*/,
            /*uint32 storePeriodLength*/,
            uint32 blockNumber
        ) = dataLayr.dataStores(headerHash);

        // verify that operator was active *at the blockNumber*
        bytes32 operatorPubkeyHash = dlRegistry.getOperatorPubkeyHash(operator);
        IDataLayrRegistry.OperatorStake memory operatorStake = dlRegistry.getStakeFromPubkeyHashAndIndex(operatorPubkeyHash, operatorHistoryIndex);
        require(
            // operator must have become active/registered before (or at) the block number
            (operatorStake.updateBlockNumber <= blockNumber) &&
            // operator must have still been active after (or until) the block number
            // either there is a later update, past the specified blockNumber, or they are still active
            (operatorStake.nextUpdateBlockNumber >= blockNumber ||
            operatorStake.nextUpdateBlockNumber == 0),
            "operator was not active during blockNumber specified by dataStoreId / headerHash"
        );

       /** 
       Check that the information supplied as input for this particular dataStore on DataLayr is correct
       */
       require(
           dataLayrServiceManager.getDataStoreIdSignatureHash(dataStoreId) ==
               keccak256(
                   abi.encodePacked(
                       dataStoreId,
                       signatoryRecord.nonSignerPubkeyHashes,
                       signatoryRecord.totalEthStakeSigned,
                       signatoryRecord.totalEigenStakeSigned
                   )
               ),
           "Sig record does not match hash"
       );

        /** 
          @notice Check that the DataLayr operator who is getting slashed was
                  actually part of the quorum for the @param dataStoreId.
          
                  The burden of responsibility lies with the challenger to show that the DataLayr operator 
                  is not part of the non-signers for the DataStore. Towards that end, challenger provides
                  @param nonSignerIndex such that if the relationship among nonSignerPubkeyHashes (nspkh) is:
                   uint256(nspkh[0]) <uint256(nspkh[1]) < ...< uint256(nspkh[index])< uint256(nspkh[index+1]),...
                  then,
                        uint256(nspkh[index]) <  uint256(operatorPubkeyHash) < uint256(nspkh[index+1])
         */
        /**
          @dev checkSignatures in DataLayrSignaturechecker.sol enforces the invariant that hash of 
               non-signers pubkey is recorded in the compressed signatory record in an  ascending
               manner.      
        */

        {
            if (signatoryRecord.nonSignerPubkeyHashes.length != 0) {
                // check that operator was *not* in the non-signer set (i.e. they *did* sign)
                challengeUtils.checkExclusionFromNonSignerSet(
                    operatorPubkeyHash,
                    nonSignerIndex,
                    signatoryRecord
                );
            }
        }

        dataLayrServiceManager.slashOperator(operator);
    }
}