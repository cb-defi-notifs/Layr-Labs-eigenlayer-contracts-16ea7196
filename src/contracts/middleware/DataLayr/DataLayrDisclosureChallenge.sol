// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IDataLayrRegistry.sol";
import "../../libraries/BytesLib.sol";
import "../../libraries/Merkle.sol";
import "../../libraries/BN254_Constants.sol";
import "../../middleware/DataLayr/DataLayrChallengeUtils.sol";


/**
 @notice This contract is for doing interactive forced disclosure and then settling it.   
 */
contract DataLayrDisclosureChallenge {
    struct DisclosureChallenge {
        // UTC timestamp (in seconds) at which the challenge was created, used for fraud proof period
        uint256 commitTime; 
        // challenger's address
        address challenger;
        // number of systematic symbols for the associated headerHash. determines how many operators must respond (at minimum)
        uint32 numSys;
        // number of symbols already disclosed
        uint32 responsesReceived;
        // chunkNumber => whether they have completed a disclosure for this challenge or not
        mapping (uint256 => bool) disclosureCompleted;
    }

    //TODO: change the time here
    uint32 constant public DISCLOSURE_CHALLENGE_RESPONSE_WINDOW = 7 days;
     // commitTime is marked as equal to 'CHALLENGE_UNSUCCESSFUL' in the event that a challenge provably fails
    uint256 constant public CHALLENGE_UNSUCCESSFUL = 1;
    // commitTime is marked as equal to 'CHALLENGE_SUCCESSFUL' in the event that a challenge succeeds
    uint256 constant public CHALLENGE_SUCCESSFUL = type(uint256).max;

    IDataLayr public immutable dataLayr;
    IDataLayrRegistry public immutable dlRegistry;
    DataLayrChallengeUtils public immutable challengeUtils;
    IDataLayrServiceManager public immutable dataLayrServiceManager;

    mapping (bytes32 => DisclosureChallenge) public disclosureChallenges;

    /**
     @notice used for notifying that a forced disclosure challenge has been initiated.
     */
    event DisclosureChallengeInit(bytes32 indexed headerHash, address challenger);
     /**
     @notice used for disclosing the multireveals and coefficients of the associated interpolating polynomial
     */
    event DisclosureChallengeResponse(bytes32 indexed headerHash,address operator, bytes poly);

    constructor(IDataLayrServiceManager _dataLayrServiceManager, IDataLayr _dataLayr, IDataLayrRegistry _dlRegistry, DataLayrChallengeUtils _challengeUtils) {
        dataLayr = _dataLayr;
        dlRegistry = _dlRegistry;
        challengeUtils = _challengeUtils;
        dataLayrServiceManager = _dataLayrServiceManager;
    }

    function forceOperatorsToDisclose(
        bytes calldata header
    ) external {
        // calculate headherHash from header
        bytes32 headerHash = keccak256(header);

        {
            /**
            Get information on the dataStore for which disperser is being challenged. This dataStore was 
            constructed during call to initDataStore in DataLayr.sol by the disperser.
            */
            (
                uint32 dumpNumber,
                uint32 initTime,
                uint32 storePeriodLength,
                // uint32 blockNumber,
                // ,
                // bool committed
            ) = dataLayr.dataStores(headerHash);

            uint256 expireTime = initTime + storePeriodLength;

            // check that disperser had acquire quorum for this dataStore
            require(dataLayrServiceManager.getDumpNumberSignatureHash(dumpNumber) != bytes32(0), "Dump is not committed yet");

            // check that the dataStore is still ongoing
            require(block.timestamp <= expireTime, "Dump has already expired");
        }

        // check that the DataLayr operator hasn't been challenged yet
        require(
            disclosureChallenges[headerHash].commitTime == 0,
            "DisclosureChallenge already opened for headerHash"
        );

        // get numSys from header
        (, , uint32 numSys, ) = challengeUtils.getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(header);

        // record details of forced disclosure challenge that has been opened
        // the current timestamp when the challenge was created
        disclosureChallenges[headerHash].commitTime = block.timestamp;
        // challenger's address
        disclosureChallenges[headerHash].challenger = msg.sender;
        disclosureChallenges[headerHash].numSys = numSys;

        emit DisclosureChallengeInit(headerHash, msg.sender);
    }


    /**
     @notice 
            Consider C(x) to be the polynomial that was used by the disperser to obtain the symbols in coded 
            chunks that was dispersed among the DataLayr operators. Let phi be an l-th root of unity, that is,
            phi^l = 1. Then, assuming each DataLayr operator has deposited same stake, 
            for the DataLayr operator k, it will receive the following symbols from the disperser:

                        C(w^k), C(w^k * phi), C(w^k * phi^2), ..., C(w^k * phi^(l-1))

            The disperser will also compute an interpolating polynomial for the DataLayr operator k that passes 
            through the above l points. Denote this interpolating polynomial by I_k(x). The disperser also 
            sends the coefficients of this interpolating polynomial I_k(x) to the DataLayr operator k. Note that
            disperser had already committed to C(s) during initDataStore, where s is the SRS generated at some
            initiation ceremony whose corresponding secret key is unknown.
            
            Observe that 

               (C - I_k)(w^k) =  (C - I)(w^k * phi) = (C - I)(w^k * phi^2) = ... = (C - I)(w^k * phi^(l-1)) = 0

            Therefore, w^k, w^k * phi, w^k * phi^2, ..., w^k * phi^l are the roots of the polynomial (C - I_k)(x).
            Therefore, one can write:

                (C - I_k)(x) = [(x - w^k) * (x - w^k * phi) * (x - w^k * phi^2) * ... * (x - w^k * phi^(l-1))] * Pi(x)
                           = [x^l - (w^k)^l] * Pi(x)

            where x^l - (w^k)^l is the zero polynomial. Let us denote the zero poly by Z_k(x) = x^l - (w^k)^l.
            
            Now, under forced disclosure, DataLayr operator k needs to just reveal the coefficients of the 
            interpolating polynomial I_k(x). The challenger for the forced disclosure can use this polynomial 
            I_k(x) to reconstruct the symbols that are stored with the DataLayr operator k which is given by:

                        I_k(w^k), I_k(w^k * phi), I_k(w^k * phi^2), ..., I_k(w^k * phi^(l-1))

            However, revealing the coefficients of I_k(x) gives no guarantee that these coefficints are correct. 
            So, we in order to respond to the forced disclosure challenge:
              (1) DataLayr operator first has to disclose proof (quotient polynomial) Pi(s) and commitment to 
                  zero polynomial Z_k(x) in order to help on-chain code to certify the commitment to the 
                  interpolating polynomial I_k(x),   
              (2) reveal the coefficients of the interpolating polynomial I_k(x) 
     */

    /**
     @notice This function is used by the DataLayr operator to respond to the forced disclosure challenge.   
     */
    /**
     @param multireveal comprises of both Pi(s) and I_k(s) in the format: [Pi(s).x, Pi(s).y, I_k(s).x, I_k(s).y]
     @param poly are the coefficients of the interpolating polynomial I_k(x)
     @param zeroPoly is the commitment to the zero polynomial x^l - (w^k)^l on group G2. The format is:
                     [Z_k(s).x0, Z_k(s).x1, Z_k(s).y0, Z_k(s).y1].    
     @param zeroPolyProof is the Merkle proof for membership of @param zeroPoly in Merkle tree
     @param header is the summary of the data that was asserted into DataLayr by the disperser during call to initDataStore,
     */
    function respondToDisclosure(
        uint256 chunkNumber,
        bytes calldata header,
        uint256[4] calldata multireveal,
        bytes calldata poly,
        uint256[4] memory zeroPoly,
        bytes calldata zeroPolyProof,
        uint256[4] calldata pi
    ) external {
        // calculate headherHash from header
        bytes32 headerHash = keccak256(header);


// TODO: should be add any of these checks / logic back in?
  //  //    // check that [zeroPoly.x0, zeroPoly.x1, zeroPoly.y0, zeroPoly.y1] is actually the "chunkNumber" leaf
    //    // of the zero polynomial Merkle tree

  //  //    // update disclosure to record Interpolating poly commitment - [I(s).x, Is(s).y]
    //    disclosureForOperator[headerHash][msg.sender].x = multireveal[2];
    //    disclosureForOperator[headerHash][msg.sender].y = multireveal[3];

  //  //    // update disclosure to record  hash of interpolating polynomial I_k(x)
    //    disclosureForOperator[headerHash][msg.sender].polyHash = keccak256(
    //        poly
    //    );

  //  //    // update disclosure to record degree of the interpolating polynomial I_k(x)
    //    disclosureForOperator[headerHash][msg.sender].degree = degree;
    //    disclosureForOperator[headerHash][msg.sender].status = 2;



// TODO: some of this code resembles some of the code in 'DataLayrLowDegreeChallenge.sol' -- determine if we can de-duplicate this code
        // check that the challenge window is still open
        require(
            (block.timestamp - disclosureChallenges[headerHash].commitTime) <= DISCLOSURE_CHALLENGE_RESPONSE_WINDOW,
            "Challenge response period has already elapsed"
        );

        // check that the submitted chunkNumber has not already been revealed for this headerHash
        require(
            !disclosureChallenges[headerHash].disclosureCompleted[chunkNumber],
            "chunkNumber already revealed for headerHash"
        );

        // actually check validity of response
        require(
            challengeUtils.nonInteractivePolynomialProof(chunkNumber, header, multireveal, poly, zeroPoly, zeroPolyProof, pi),
            "noninteractive polynomial proof failed"
        );

        // record that the chunkNumber has been disclosed
        disclosureChallenges[headerHash].disclosureCompleted[chunkNumber] = true;
        disclosureChallenges[headerHash].responsesReceived += 1;

        // mark challenge as failing in the event that at least numSys operators have responded
        if (disclosureChallenges[headerHash].responsesReceived >= disclosureChallenges[headerHash].numSys) {
            disclosureChallenges[headerHash].commitTime = CHALLENGE_UNSUCCESSFUL;
        }

        // emit event
        emit DisclosureChallengeResponse(headerHash, msg.sender, poly);
    }
    
    // TODO: this is essentially copy-pasted from 'DataLayrLowDegreeChallenge.sol' -- de-duplicate this code!
    function resolveDisclosureChallenge(bytes32 headerHash) public {
        require(disclosureChallenges[headerHash].commitTime != 0, "Challenge does not exist");
        require(disclosureChallenges[headerHash].commitTime != CHALLENGE_UNSUCCESSFUL, "Challenge failed");
        // check that the challenge window is no longer open
        require(
            (block.timestamp - disclosureChallenges[headerHash].commitTime) > DISCLOSURE_CHALLENGE_RESPONSE_WINDOW,
            "Challenge response period has not yet elapsed"
        );

        // set challenge commit time equal to 'CHALLENGE_SUCCESSFUL', so the same challenge cannot be opened a second time,
        // and to signal that the challenge has been lost by the signers
        disclosureChallenges[headerHash].commitTime = CHALLENGE_SUCCESSFUL;
        // dataLayrServiceManager.resolveDisclosureChallenge(headerHash, disclosureChallenges[headerHash].commitTime);
    }

    // TODO: this is essentially copy-pasted from 'DataLayrLowDegreeChallenge.sol' -- de-duplicate this code!
    // slash an operator who signed a headerHash but failed a subsequent DisclosureChallenge
    function slashOperator(
        bytes32 headerHash,
        address operator,
        uint256 nonSignerIndex,
        uint32 operatorHistoryIndex,
        IDataLayrServiceManager.SignatoryRecordMinusDumpNumber calldata signatoryRecord
    ) external {
        // verify that the challenge has been lost
        require(disclosureChallenges[headerHash].commitTime == CHALLENGE_SUCCESSFUL, "Challenge not successful");

        /**
        Get information on the dataStore for which disperser is being challenged. This dataStore was 
        constructed during call to initDataStore in DataLayr.sol by the disperser.
        */
        (
            uint32 dumpNumber,
            uint32 blockNumber,
            ,
            
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
            "operator was not active during blockNumber specified by dumpNumber / headerHash"
        );

       /** 
       Check that the information supplied as input for this particular dataStore on DataLayr is correct
       */
       require(
           dataLayrServiceManager.getDumpNumberSignatureHash(dumpNumber) ==
               keccak256(
                   abi.encodePacked(
                       dumpNumber,
                       signatoryRecord.nonSignerPubkeyHashes,
                       signatoryRecord.totalEthStakeSigned,
                       signatoryRecord.totalEigenStakeSigned
                   )
               ),
           "Sig record does not match hash"
       );

        /** 
          @notice Check that the DataLayr operator against whom forced disclosure is being initiated, was
                  actually part of the quorum for the @param dumpNumber.
          
                  The burden of responsibility lies with the challenger to show that the DataLayr operator 
                  is not part of the non-signers for the dump. Towards that end, challenger provides
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
                // check that operator was *not* in the non-signer set (i.e. they did sign)
                //not super critic: new call here, maybe change comment
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
