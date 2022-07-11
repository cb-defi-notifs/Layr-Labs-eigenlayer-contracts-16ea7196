// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../libraries/BytesLib.sol";
import "../../libraries/Merkle.sol";
import "../../libraries/BN254_Constants.sol";
import "./DataLayrChallengeBase.sol";

/**
 @notice This contract is for doing interactive forced disclosure and then settling it.   
 */
contract DataLayrDisclosureChallenge is DataLayrChallengeBase {
    struct DisclosureChallenge {
        // UTC timestamp (in seconds) at which the challenge was created, used for fraud proof period
        uint256 commitTime; 
        // challenger's address
        address challenger;
        // number of systematic symbols for the associated headerHash. determines how many operators must respond (at minimum)
        uint32 numSys;
        // number of symbols already disclosed
        uint32 responsesReceived;
        // collateral amount associated with the challenge
        uint256 collateral;
        // chunkNumber => whether they have completed a disclosure for this challenge or not
        mapping (uint256 => bool) disclosureCompleted;
    }

    // length of window during which the responses can be made to the challenge
    uint32 internal constant  _DISCLOSURE_CHALLENGE_RESPONSE_WINDOW = 7 days;

    // amount of token required to be placed as collateral when a challenge is opened
    uint256 internal constant _DISCLOSURE_CHALLENGE_COLLATERAL_AMOUNT = 1e18;

    mapping (bytes32 => DisclosureChallenge) public disclosureChallenges;

    /**
     @notice used for notifying that a forced disclosure challenge has been initiated.
     */
    event DisclosureChallengeInit(bytes32 indexed headerHash, address challenger);
     /**
     @notice used for disclosing the multireveals and coefficients of the associated interpolating polynomial
     */
    event DisclosureChallengeResponse(bytes32 indexed headerHash,address operator, bytes poly);

    constructor(
        IDataLayrServiceManager _dataLayrServiceManager,
        IDataLayr _dataLayr,
        IRegistry _dlRegistry,
        DataLayrChallengeUtils _challengeUtils
    )   DataLayrChallengeBase(_dataLayrServiceManager, _dataLayr, _dlRegistry, _challengeUtils, _DISCLOSURE_CHALLENGE_RESPONSE_WINDOW, _DISCLOSURE_CHALLENGE_COLLATERAL_AMOUNT)
    {
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
            (block.timestamp - disclosureChallenges[headerHash].commitTime) <= CHALLENGE_RESPONSE_WINDOW,
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

    function challengeSuccessful(bytes32 headerHash) public view override returns (bool) {
        return (disclosureChallenges[headerHash].commitTime == CHALLENGE_SUCCESSFUL);
    }

    function challengeUnsuccessful(bytes32 headerHash) public view override returns (bool) {
        return (disclosureChallenges[headerHash].commitTime == CHALLENGE_UNSUCCESSFUL);
    }

    function challengeExists(bytes32 headerHash) public view override returns (bool) {
        return (disclosureChallenges[headerHash].commitTime != 0);
    }

    function challengeClosed(bytes32 headerHash) public view override returns (bool) {
        return ((block.timestamp - disclosureChallenges[headerHash].commitTime) > CHALLENGE_RESPONSE_WINDOW);
    }

    // set challenge commit time equal to 'CHALLENGE_SUCCESSFUL', so the same challenge cannot be opened a second time,
    // and to signal that the challenge has been lost by the signers
    function _markChallengeSuccessful(bytes32 headerHash) internal override {
        disclosureChallenges[headerHash].commitTime = CHALLENGE_SUCCESSFUL;
    }

    function _recordChallengeDetails(bytes calldata header, bytes32 headerHash) internal override {
        // get numSys from header
        (, , uint32 numSys, ) = challengeUtils.getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(header);

        // record details of forced disclosure challenge that has been opened
        // the current timestamp when the challenge was created
        disclosureChallenges[headerHash].commitTime = block.timestamp;
        // challenger's address
        disclosureChallenges[headerHash].challenger = msg.sender;
        disclosureChallenges[headerHash].numSys = numSys;
    }

    function _challengeCreationEvent(bytes32 headerHash) internal override {
        emit DisclosureChallengeInit(headerHash, msg.sender);
    }
}
