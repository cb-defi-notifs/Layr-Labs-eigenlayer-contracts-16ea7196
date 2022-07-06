// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrRegistry.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../middleware/DataLayr/DataLayrChallengeUtils.sol";

abstract contract DataLayrChallengeBase {
    IDataLayr public immutable dataLayr;
    IDataLayrRegistry public immutable dlRegistry;
    DataLayrChallengeUtils public immutable challengeUtils;
    IDataLayrServiceManager public immutable dataLayrServiceManager;

    constructor(
        IDataLayrServiceManager _dataLayrServiceManager,
        IDataLayr _dataLayr,
        IDataLayrRegistry _dlRegistry,
        DataLayrChallengeUtils _challengeUtils
    ) {
        dataLayrServiceManager = _dataLayrServiceManager;
        dataLayr = _dataLayr;
        dlRegistry = _dlRegistry;
        challengeUtils = _challengeUtils;
    }

	function challengeSuccessful(bytes32 headerHash) public view virtual returns (bool);

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

        // TODO: actually slash.
    }
}