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

/**
 * @title Used to create and manage low degree challenges related to DataLayr.
 * @author Layr Labs, Inc.
 */
contract DataLayrLowDegreeChallenge is DataLayrChallengeBase {
    using SafeERC20 for IERC20;

    struct LowDegreeChallenge {
        // UTC timestamp (in seconds) at which the challenge was created, used for fraudproof period
        uint256 commitTime;
        // challenger's address
        address challenger;
    }

    // length of window during which the responses can be made to the challenge
    uint32 internal constant _DEGREE_CHALLENGE_RESPONSE_WINDOW = 7 days;

    // headerHash => LowDegreeChallenge struct
    mapping(bytes32 => LowDegreeChallenge) public lowDegreeChallenges;

    event SuccessfulLowDegreeChallenge(
        bytes32 indexed headerHash,
        address challenger
    );
    uint256 internal constant MAX_POT_DEGREE = (2 ** 28);

    constructor(
        IDataLayrServiceManager _dataLayrServiceManager,
        IQuorumRegistry _dlRegistry,
        DataLayrChallengeUtils _challengeUtils
    )
        DataLayrChallengeBase(
            _dataLayrServiceManager,
            _dlRegistry,
            _challengeUtils,
            0,
            0
        )
    // solhint-disable-next-line no-empty-blocks
    {}

    /**
     * @notice This function tests whether a polynomial's degree is not greater than a provided degree
     * @param header is the header information, which contains the kzg metadata (commitment and degree to check against)
     * @param potElement is the G2 point of the POT element we are computing the pairing for (x^{n-m})
     * @param proofInG1 is the provided G1 point is the product of the POTElement and the polynomial, i.e., [(x^{n-m})*p(x)]_1
     * We are essentially computing the pairing e([p(x)]_1, [x^{n-m}]_2) = e([(x^{n-m})*p(x)]_1, [1]_2)
     */

    //TODO: we need to hardcode a merkle root hash in storage
    function lowDegreenessProof(
        bytes calldata header,
        BN254.G2Point memory potElement,
        bytes memory potMerkleProof,
        BN254.G1Point memory proofInG1
    )
        external
        view
    {
        //retreiving the kzg commitment to the data in the form of a polynomial
        DataLayrChallengeUtils.DataStoreKZGMetadata memory dskzgMetadata =
            challengeUtils.getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(header);

        //the index of the merkle tree containing the potElement
        uint256 potIndex = MAX_POT_DEGREE - dskzgMetadata.degree * challengeUtils.nextPowerOf2(dskzgMetadata.numSys);
        //computing hash of the powers of Tau element to verify merkle inclusion
        bytes32 hashOfPOTElement = keccak256(abi.encodePacked(potElement.X, potElement.Y));
        require(
            Merkle.checkMembership(hashOfPOTElement, potIndex, BLS.powersOfTauMerkleRoot, potMerkleProof),
            "Merkle proof was not validated"
        );

        BN254.G2Point memory negativeG2 = BN254.G2Point({X: [BLS.nG2x1, BLS.nG2x0], Y: [BLS.nG2y1, BLS.nG2y0]});
        require(
            BN254.pairing(dskzgMetadata.c, potElement, proofInG1, negativeG2),
            "DataLayreLowDegreeChallenge.lowDegreenessCheck: Pairing Failed"
        );
    }

    function respondToLowDegreeChallenge(
        bytes calldata header,
        uint256[2] calldata cPower,
        uint256[4] calldata pi,
        uint256[4] calldata piPower,
        uint256 s,
        uint256 sPrime
    )
        external
    {
        //TODO: Implement this
        // bytes32 headerHash = keccak256(header);

        // // check that the challenge window is still open
        // require(
        //     (block.timestamp - lowDegreeChallenges[headerHash].commitTime) <=
        //         CHALLENGE_RESPONSE_WINDOW,
        //     "Challenge response period has already elapsed"
        // );

        // DataLayrChallengeUtils.DataStoreKZGMetadata memory dskzgMetaData = challengeUtils
        //     .getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(
        //         header
        //     );

        // uint256 r = uint256(keccak256(abi.encodePacked(dskzgMetaData.c, cPower))) % MODULUS;

        // require(
        //     challengeUtils.openPolynomialAtPoint(dskzgMetaData.c, pi, r, s),
        //     "Incorrect proof against commitment"
        // );

        // // TODO: make sure this is the correct power -- shouldn't it actually be (32 - this number) ? -- @Gautham
        // uint256 power = challengeUtils.nextPowerOf2(dskzgMetaData.numSys) *
        //     challengeUtils.nextPowerOf2(dskzgMetaData.degree);

        // uint256 rPower;

        // // call modexp precompile at 0x05 to calculate r^power mod (MODULUS)
        // assembly {
        //     let freemem := mload(0x40)
        //     // base size is 32 bytes
        //     mstore(freemem, 0x20)
        //     // exponent size is 32 bytes
        //     mstore(add(freemem, 0x20), 0x20)
        //     // modulus size is 32 bytes
        //     mstore(add(freemem, 0x40), 0x20)
        //     // specifying base as 'r'
        //     mstore(add(freemem, 0x60), r)
        //     // specifying exponent as 'power'
        //     mstore(add(freemem, 0x80), power)
        //     // specifying modulus as 21888242871839275222246405745257275088696311157297823662689037894645226208583 (i.e. "MODULUS") in hex
        //     mstore(
        //         add(freemem, 0xA0),
        //         0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
        //     )
        //     // staticcall returns 0 in the case that it reverted, in which case we also want to revert
        //     if iszero(
        //         // call modexp precompile with parameters specified above, copying the (single, 32 byte) return value to the freemem location
        //         staticcall(sub(gas(), 2000), 5, freemem, 0xC0, freemem, 0x20)
        //     ) {
        //         revert(0, 0)
        //     }
        //     // store the returned value in 'sPower'
        //     rPower := mload(freemem)
        // }

        // require(
        //     challengeUtils.openPolynomialAtPoint(cPower, piPower, r, sPrime),
        //     "Incorrect proof against commitment power"
        // );

        // // verify that r^power * s mod (MODULUS) == sPrime
        // uint256 res;
        // assembly {
        //     res := mulmod(rPower, s, MODULUS)
        // }
        // require(res == sPrime, "bad sPrime provided");

        // // set challenge commit time equal to 'CHALLENGE_UNSUCCESSFUL', so the same challenge cannot be opened a second time,
        // // and to signal that the msg.sender correctly answered the challenge
        // lowDegreeChallenges[headerHash].commitTime = CHALLENGE_UNSUCCESSFUL;

        // // send challenger collateral to msg.sender
        // IERC20 collateralToken = dataLayrServiceManager.collateralToken();
        // collateralToken.safeTransfer(msg.sender, lowDegreeChallenges[headerHash].collateral);
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

    function _returnChallengerCollateral(bytes32) internal pure override {
        return;
    }
}