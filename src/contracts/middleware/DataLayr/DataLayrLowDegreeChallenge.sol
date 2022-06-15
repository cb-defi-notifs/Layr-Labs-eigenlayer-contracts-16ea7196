import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IRepository.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IDataLayr.sol";
import "../../interfaces/IDataLayrRegistry.sol";
import "../Repository.sol";
import "./DataLayrChallengeUtils.sol";
import "./DataLayrLowDegreeChallenge.sol";

contract DataLayrLowDegreeChallenge {
        // Field order
    uint256 constant MODULUS =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;

    IDataLayr public immutable dataLayr;
    IDataLayrRegistry public immutable dlRegistry;
    DataLayrChallengeUtils public immutable challengeUtils;
    IDataLayrServiceManager public immutable dataLayrServiceManager;

    struct LowDegreeChallenge {
        uint32 commitTime; 
        address challenge;
        uint256 collateral; //account for if collateral changed
    }
    mapping(bytes32 => mapping(address => LowDegreeChallenge)) public lowDegreeChallenges;

    event LowDegreeChallengeInit(
        bytes32 headerHash,
        address operator,
        address challenger
    );

    constructor(IDataLayrServiceManager _dataLayrServiceManager, IDataLayr _dataLayr, IDataLayrRegistry _dlRegistry, DataLayrChallengeUtils _challengeUtils) {
        dataLayr = _dataLayr;
        dlRegistry = _dlRegistry;
        challengeUtils = _challengeUtils;
        dataLayrServiceManager = _dataLayrServiceManager;
    }

    function forceOperatorToProveLowDegree(
        bytes32 headerHash,
        address operator,
        uint32 operatorIndex,
        uint32 totalOperatorsIndex,
        uint256 nonSignerIndex,
        IDataLayrServiceManager.SignatoryRecordMinusDumpNumber calldata signatoryRecord
    ) public {
        uint32 chunkNumber;
        uint32 expireTime;

        {
            /**
            Get information on the dataStore for which disperser is being challenged. This dataStore was 
            constructed during call to initDataStore in DataLayr.sol by the disperser.
            */
            (
                uint32 dumpNumber,
                uint32 expireTime,
                uint32 storePeriodLength,
                uint32 blockNumber,
                bool committed
            ) = dataLayr.dataStores(headerHash);

            expireTime = expireTime + storePeriodLength;

            // check that disperser had acquire quorum for this dataStore
            require(committed, "Dump is not committed yet");

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

            operatorIndex = dlRegistry.getOperatorIndex(
                operator,
                dumpNumber,
                operatorIndex
            );
            totalOperatorsIndex = dlRegistry.getTotalOperators(
                dumpNumber,
                totalOperatorsIndex
            );
            chunkNumber = (operatorIndex + dumpNumber) % totalOperatorsIndex;
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
                //not super critic: new call here, maybe change comment
                challengeUtils.checkInclusionExclusionInNonSigner(
                    operatorPubkeyHash,
                    nonSignerIndex,
                    signatoryRecord
                );
            }
        }

        // check that the DataLayr operator hasn't been challenged yet
        require(
            lowDegreeChallenges[headerHash][operator].commitTime == 0,
            "Operator is already challenged for dump number"
        );

        // record details of forced disclosure challenge that has been opened
        lowDegreeChallenges[headerHash][operator] = LowDegreeChallenge(
            // the current timestamp when the challenge was created
            uint32(block.timestamp),
            // challenger's address
            msg.sender,
            0
        );

        emit LowDegreeChallengeInit(headerHash, operator, msg.sender);
    }

    function respondToLowDegreeChallenge(
        bytes calldata header,
        uint256[2] calldata cPower,
        uint256[4] calldata pi,
        uint256[4] calldata piPower,
        uint256 s
    ) external {
        bytes32 headerHash = keccak256(header);

        // check that it is DataLayr operator who is supposed to respond
        //TODO: change the time here
        require(
            block.timestamp -
                lowDegreeChallenges[headerHash][msg.sender].commitTime <
                7 * 24 * 60 * 60,
            "Passed fraud proof period on "
        );

        (
            uint256[2] memory c,
            uint48 degree,
            uint32 numSys,
            uint32 numPar
        ) = challengeUtils
                .getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(
                    header
                );

        uint256 r = uint256(keccak256(abi.encodePacked(c, cPower))) % MODULUS;

        require(
            challengeUtils.openPolynomialAtPoint(c, pi, r, s),
            "Incorrect proof against commitment"
        );

        uint256 power = challengeUtils.nextPowerOf2(numSys) *
            challengeUtils.nextPowerOf2(degree);

        uint256 sPower;

        assembly {
            let freemem := mload(0x40)
            mstore(freemem, 0x20)
            mstore(add(freemem, 0x20), 0x20)
            mstore(add(freemem, 0x40), 0x20)
            mstore(add(freemem, 0x60), s)
            mstore(add(freemem, 0x80), power)
            mstore(
                add(freemem, 0xA0),
                0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
            )
            if iszero(
                staticcall(sub(gas(), 2000), 5, freemem, 0xC0, freemem, 0x20)
            ) {
                revert(0, 0)
            }
            sPower := mload(freemem)
        }

        require(
            challengeUtils.openPolynomialAtPoint(cPower, piPower, r, sPower),
            "Incorrect proof against commitment power"
        );

        lowDegreeChallenges[headerHash][msg.sender].commitTime = 1;
        dataLayrServiceManager.resolveLowDegreeChallenge(headerHash, msg.sender, 1);
    }

    function resolveLowDegreeChallenge(bytes32 headerHash, address operator) public {
        dataLayrServiceManager.resolveLowDegreeChallenge(headerHash, operator, lowDegreeChallenges[headerHash][operator].commitTime);
    }
}