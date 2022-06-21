// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IRepository.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IDataLayr.sol";
import "../../interfaces/IDataLayrRegistry.sol";
import "../Repository.sol";
import "./DataLayrChallengeUtils.sol";

// TODO: collateral
contract DataLayrLowDegreeChallenge {
    struct LowDegreeChallenge {
        // UTC timestamp (in seconds) at which the challenge was created
        uint256 commitTime; 
        // challenger's address
        address challenge;
        // account for if collateral changed
        uint256 collateral;
    }

    // Field order
    uint256 constant MODULUS = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
    //TODO: change the time here
    uint32 constant public CHALLENGE_RESPONSE_WINDOW = 7 days;

    IDataLayr public immutable dataLayr;
    IDataLayrRegistry public immutable dlRegistry;
    DataLayrChallengeUtils public immutable challengeUtils;
    IDataLayrServiceManager public immutable dataLayrServiceManager;

    event LowDegreeChallengeInit(
        bytes32 indexed headerHash,
        address challenger
    );

    constructor(IDataLayrServiceManager _dataLayrServiceManager, IDataLayr _dataLayr, IDataLayrRegistry _dlRegistry, DataLayrChallengeUtils _challengeUtils) {
        dataLayr = _dataLayr;
        dlRegistry = _dlRegistry;
        challengeUtils = _challengeUtils;
        dataLayrServiceManager = _dataLayrServiceManager;
    }

    // headerHash => LowDegreeChallenge struct
    mapping(bytes32 => LowDegreeChallenge) public lowDegreeChallenges;

    function forceOperatorsToProveLowDegree(
        bytes32 headerHash
    ) public {
        {
            /**
            Get information on the dataStore for which disperser is being challenged. This dataStore was 
            constructed during call to initDataStore in DataLayr.sol by the disperser.
            */
            (
                // uint32 dumpNumber,
                ,
                uint32 initTime,
                uint32 storePeriodLength,
                // uint32 blockNumber,
                ,
                bool committed
            ) = dataLayr.dataStores(headerHash);

            uint256 expireTime = initTime + storePeriodLength;

            // check that disperser had acquire quorum for this dataStore
            require(committed, "Dump is not committed yet");

            // check that the dataStore is still ongoing
            require(block.timestamp <= expireTime, "Dump has already expired");
        }

        // check that the DataLayr operator hasn't been challenged yet
        require(
            lowDegreeChallenges[headerHash].commitTime == 0,
            "LowDegreeChallenge is already opened for headerHash"
        );

        // record details of forced disclosure challenge that has been opened
        lowDegreeChallenges[headerHash] = LowDegreeChallenge(
            // the current timestamp when the challenge was created
            block.timestamp,
            // challenger's address
            msg.sender,
            0
        );

        emit LowDegreeChallengeInit(headerHash, msg.sender);
    }

    function respondToLowDegreeChallenge(
        bytes calldata header,
        uint256[2] calldata cPower,
        uint256[4] calldata pi,
        uint256[4] calldata piPower,
        uint256 s,
        uint256 sPrime
    ) external {
        bytes32 headerHash = keccak256(header);

        // check that the challenge window is still open
        require(
            (block.timestamp - lowDegreeChallenges[headerHash].commitTime) <= CHALLENGE_RESPONSE_WINDOW,
            "Challenge response period has already elapsed"
        );

        (
            uint256[2] memory c,
            uint48 degree,
            uint32 numSys,
            // uint32 numPar -- commented out return variable
            
        ) = challengeUtils
                .getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(
                    header
                );

        uint256 r = uint256(keccak256(abi.encodePacked(c, cPower))) % MODULUS;

        require(
            challengeUtils.openPolynomialAtPoint(c, pi, r, s),
            "Incorrect proof against commitment"
        );

        // TODO: make sure this is the correct power -- shouldn't it actually be (32 - this number) ? -- @Gautham
        uint256 power = challengeUtils.nextPowerOf2(numSys) *
            challengeUtils.nextPowerOf2(degree);

        uint256 rPower;

        // call modexp precompile at 0x05 to calculate r^power mod (MODULUS)
        assembly {
            let freemem := mload(0x40)
            // base size is 32 bytes
            mstore(freemem, 0x20)
            // exponent size is 32 bytes
            mstore(add(freemem, 0x20), 0x20)
            // modulus size is 32 bytes
            mstore(add(freemem, 0x40), 0x20)
            // specifying base as 'r'
            mstore(add(freemem, 0x60), r)
            // specifying exponent as 'power'
            mstore(add(freemem, 0x80), power)
            // specifying modulus as 21888242871839275222246405745257275088696311157297823662689037894645226208583 (i.e. "MODULUS") in hex
            mstore(
                add(freemem, 0xA0),
                0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            )
            // staticcall returns 0 in the case that it reverted, in which case we also want to revert
            if iszero(
                // call modexp precompile with parameters specified above, copying the (single, 32 byte) return value to the freemem location 
                staticcall(sub(gas(), 2000), 5, freemem, 0xC0, freemem, 0x20)
            ) {
                revert(0, 0)
            }
            // store the returned value in 'sPower'
            rPower := mload(freemem)
        }

        require(
            challengeUtils.openPolynomialAtPoint(cPower, piPower, r, sPrime),
            "Incorrect proof against commitment power"
        );

        // verify that r^power * s mod (MODULUS) == sPrime
        uint256 res;
        assembly {
            res := mulmod(rPower, s, MODULUS)
        }
        require(res == sPrime, "bad sPrime provided");

        // set challenge commit time equal to '1', so the same challenge cannot be opened a second time,
        // and to signal that the msg.sender correctly answered the challenge
        lowDegreeChallenges[headerHash].commitTime = 1;
        // TODO: pay collateral to msg.sender
        // dataLayrServiceManager.resolveLowDegreeChallenge(headerHash, msg.sender, 1);
    }

    function resolveLowDegreeChallenge(bytes32 headerHash) public {
        require(lowDegreeChallenges[headerHash].commitTime != 0, "Challenge does not exist");
        require(lowDegreeChallenges[headerHash].commitTime != 1, "Challenge failed");
        // check that the challenge window is no longer open
        require(
            (block.timestamp - lowDegreeChallenges[headerHash].commitTime) > CHALLENGE_RESPONSE_WINDOW,
            "Challenge response period has not yet elapsed"
        );

        // set challenge commit time equal to max possible value, so the same challenge cannot be opened a second time,
        // and to signal that the challenge has been lost by the signers
        lowDegreeChallenges[headerHash].commitTime = type(uint256).max;
        // dataLayrServiceManager.resolveLowDegreeChallenge(headerHash, lowDegreeChallenges[headerHash].commitTime);
    }

    // slash an operator who signed a headerHash but failed a subsequent LowDegreeChallenge
    function slashOperator(
        bytes32 headerHash,
        address operator,
        // uint32 operatorIndex,
        // uint32 totalOperatorsIndex,
        uint256 nonSignerIndex,
        IDataLayrServiceManager.SignatoryRecordMinusDumpNumber calldata signatoryRecord
    ) public {
        // verify that the challenge has been lost
        require(lowDegreeChallenges[headerHash].commitTime == type(uint256).max, "Challenge has not been lost");

        {
            /**
            Get information on the dataStore for which disperser is being challenged. This dataStore was 
            constructed during call to initDataStore in DataLayr.sol by the disperser.
            */
            (
                uint32 dumpNumber,
                uint32 blockNumber,
                ,
                ,
                
            ) = dataLayr.dataStores(headerHash);
// TODO: verify that operator was active *at the blockNumber*


            /** 
            Check that the information supplied as input for forced disclosure for this particular data 
            dump on DataLayr is correct
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
/* TODO: determine if this is useful at all
            // lookup operator's spot in list of all operators at time, specified by operator, dumpNumber, and index in operator's history
            operatorIndex = dlRegistry.getOperatorIndex(
                operator,
                dumpNumber,
                operatorIndex
            );
            // lookup number of total operators at time, specified by dumpNumber, and index in history of totalOperators
            totalOperatorsIndex = dlRegistry.getTotalOperators(
                dumpNumber,
                totalOperatorsIndex
            );
*/
        }

        /** 
          @notice Check that the DataLayr operator against whom forced disclosure is being initiated, was
                  actually part of the quorum for the @param dumpNumber.
          
                  The burden of responsibility lies with the challenger to show that the DataLayr operator 
                  is not part of the non-signers for the dump. Towards that end, challenger provides
                  @param index such that if the relationship among nonSignerPubkeyHashes (nspkh) is:
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
                // get the pubkey hash of the DataLayr operator
                bytes32 operatorPubkeyHash = dlRegistry.getOperatorPubkeyHash(
                    operator
                );
                // check that operator was *not* in the non-signer set (i.e. they did sign)
                //not super critic: new call here, maybe change comment
                challengeUtils.checkInclusionExclusionInNonSigner(
                    operatorPubkeyHash,
                    nonSignerIndex,
                    signatoryRecord
                );
            }
        }

        // TODO: actually slash.
    }
}