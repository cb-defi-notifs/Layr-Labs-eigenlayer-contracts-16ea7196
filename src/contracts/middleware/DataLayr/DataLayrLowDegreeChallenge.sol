// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/IRepository.sol";
import "../../interfaces/IQuorumRegistry.sol";

import "../Repository.sol";

import "./DataLayrChallengeUtils.sol";
import "./DataLayrChallengeBase.sol";

import "../../libraries/Merkle.sol";
import "../../libraries/BLS.sol";

contract DataLayrLowDegreeChallenge is DataLayrChallengeBase {
    using SafeERC20 for IERC20;
    
    struct LowDegreeChallenge {
        // UTC timestamp (in seconds) at which the challenge was created, used for fraudproof period
        uint256 commitTime;
        // challenger's address
        address challenger;
    }

    uint256 internal constant MAX_POT_DEGREE = (2**28);

    // headerHash => LowDegreeChallenge struct
    mapping(bytes32 => LowDegreeChallenge) public lowDegreeChallenges;

    event SuccessfulLowDegreeChallenge(
        bytes32 indexed headerHash,
        address challenger
    );


    constructor(
        IDataLayrServiceManager _dataLayrServiceManager,
        IQuorumRegistry _dlRegistry,
        DataLayrChallengeUtils _challengeUtils
    )   DataLayrChallengeBase(_dataLayrServiceManager, _dlRegistry, _challengeUtils, 0, 0)
    {
    }


    /// @notice This function tests whether a polynomial's degree is not greater than a provided degree
    /// @param header is the header information, which contains the kzg metadata (commitment and degree to check against)
    /// @param potElement is the G2 point of the POT element we are computing the pairing for (x^{n-m})
    /// @param proofInG1 is the provided G1 point is the product of the POTElement and the polynomial, i.e., [(x^{n-m})*p(x)]_1
    /// We are essentially computing the pairing e([p(x)]_1, [x^{n-m}]_2) = e([(x^{n-m})*p(x)]_1, [1]_2)

    //TODO: we need to hardcode a merkle root hash in storage
    function lowDegreenessProof(
        bytes calldata header,
        BN254.G2Point memory potElement,
        bytes memory potMerkleProof,
        BN254.G1Point memory proofInG1
    ) external view {

        //retreiving the kzg commitment to the data in the form of a polynomial
        DataLayrChallengeUtils.DataStoreKZGMetadata memory dskzgMetadata = challengeUtils.getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(header);

        //the index of the merkle tree containing the potElement
        uint256 potIndex = MAX_POT_DEGREE - dskzgMetadata.degree * challengeUtils.nextPowerOf2(dskzgMetadata.numSys);
        //computing hash of the powers of Tau element to verify merkle inclusion
        bytes32 hashOfPOTElement = keccak256(abi.encodePacked(potElement.X, potElement.Y));
        require(Merkle.checkMembership(hashOfPOTElement, potIndex, BLS.powersOfTauMerkleRoot, potMerkleProof), "Merkle proof was not validated");

        BN254.G2Point memory negativeG2 = BN254.G2Point({X: [BLS.nG2x1, BLS.nG2x0], Y: [BLS.nG2y1, BLS.nG2y0]});
        require(BN254.pairing(dskzgMetadata.c, potElement, proofInG1, negativeG2), "DataLayreLowDegreeChallenge.lowDegreenessCheck: Pairing Failed");
        //TODO: WIP, need to integrate slashing here
    }


    function challengeSuccessful(bytes32 headerHash) public view override returns (bool) {
        return (lowDegreeChallenges[headerHash].commitTime == CHALLENGE_SUCCESSFUL);
    }

    function challengeUnsuccessful(bytes32 headerHash) public view override returns (bool) {
        return (lowDegreeChallenges[headerHash].commitTime == CHALLENGE_UNSUCCESSFUL);
    }

    function challengeExists(bytes32 headerHash) public view override returns (bool) {
        return (lowDegreeChallenges[headerHash].commitTime != 0);
    }

    function challengeClosed(bytes32 headerHash) public view override returns (bool) {
        return ((block.timestamp - lowDegreeChallenges[headerHash].commitTime) > CHALLENGE_RESPONSE_WINDOW);
    }

    // set challenge commit time equal to 'CHALLENGE_SUCCESSFUL', so the same challenge cannot be opened a second time,
    // and to signal that the challenge has been lost by the signers
    function _markChallengeSuccessful(bytes32 headerHash) internal override {
        lowDegreeChallenges[headerHash].commitTime = CHALLENGE_SUCCESSFUL;
    }

    function _recordChallengeDetails(bytes calldata, bytes32 headerHash) internal override {
        // record details of low degree challenge that has been opened
        lowDegreeChallenges[headerHash] = LowDegreeChallenge(
            // the current timestamp when the challenge was created
            block.timestamp,
            // challenger's address
            msg.sender
        );
    }

    function _challengeCreationEvent(bytes32 headerHash) internal override {
        emit SuccessfulLowDegreeChallenge(headerHash, msg.sender);
    }

    function _returnChallengerCollateral(bytes32 headerHash) internal override {
        return;
    }
}