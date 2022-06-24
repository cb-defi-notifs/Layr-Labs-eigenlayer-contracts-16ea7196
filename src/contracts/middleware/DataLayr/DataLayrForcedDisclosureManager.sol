// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrRegistry.sol";
import "../../interfaces/IRepository.sol";
import "../../interfaces/IDataLayr.sol";
import "../../interfaces/IDataLayrForcedDisclosureManager.sol";
import "./DataLayrChallengeUtils.sol";
import "./DataLayrDisclosureChallengeFactory.sol";
import "../../interfaces/IDataLayrServiceManager.sol";


import "ds-test/test.sol";

contract DataLayrForcedDisclosureManager is DSTest{
    // modulus for the underlying field F_q of the elliptic curve
    uint256 constant MODULUS =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;
    // negation of the generators of group G2
    /**
     @dev Generator point lies in F_q2 is of the form: (x0 + ix1, y0 + iy1).
     */
    uint256 constant nG2x1 =
        11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 constant nG2x0 =
        10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 constant nG2y1 =
        17805874995975841540914202342111839520379459829704422454583296818431106115052;
    uint256 constant nG2y0 =
        13392588948715843804641432497768002650278120570034223513918757245338268106653;

    bytes32 public powersOfTauMerkleRoot = 0x22c998e49752bbb1918ba87d6d59dd0e83620a311ba91dd4b2cc84990b31b56f;

    //STRUCTS
    /**
     @notice used for storing information on the forced disclosure challenge    
    */
    struct DisclosureChallenge {
        // instant when forced disclosure challenge was made
        uint32 commitTime;
        // challenger's address
        address challenger; 
        // address of challenge contract if there is one - updated in initInterpolatingPolynomialFraudProof function
        // in DataLayrServiceManager.sol 
        address challenge;
        uint48 degree;
        /** 
            Used for indicating the status of the forced disclosure challenge. The status are:
                - 1: challenged, 
                - 2: responded (in fraud proof period), 
                - 3: challenged commitment, 
                - 4: operator incorrect
         */
        uint8 status; 
        // Proof [Pi(s).x, Pi(s).y] with respect to C(s) - I_k(s)
        // updated in respondToDisclosureInit function in DataLayrServiceManager.sol 
        uint256 x; //commitment coordinates
        uint256 y;
        bytes32 polyHash;
        uint32 chunkNumber;
        uint256 collateral; //account for if collateral changed
    }

    //MAPPINGS
    /**
     @notice map of forced disclosure challenge that has been opened against a DataLayr operator
             for a particular dump number.   
     */
    mapping(bytes32 => mapping(address => DisclosureChallenge)) public disclosureForOperator;
    /**
     * @notice mapping between the dumpNumber for a particular assertion of data into
     *         DataLayr and a compressed information on the signatures of the DataLayr 
     *         nodes who signed up to be the part of the quorum.  
     */
    mapping(uint64 => bytes32) public dumpNumberToSignatureHash;

    IRepository public repository;
    IDataLayr public dataLayr;
    DataLayrChallengeUtils public immutable challengeUtils;
    DataLayrDisclosureChallengeFactory public immutable dataLayrDisclosureChallengeFactory;



    // EVENTS
    /**
     @notice used for notifying that disperser has initiated a forced disclosure challenge.
     */
    event DisclosureChallengeInit(bytes32 headerHash, address operator);
     /**
     @notice used for disclosing the multireveals and coefficients of the associated interpolating polynomial
     */
    event DisclosureChallengeResponse(bytes32 headerHash,address operator,bytes poly);
    /**
     @notice used while initializing the interactive forced disclosure
     */
    event DisclosureChallengeInteractive(bytes32 headerHash, address disclosureChallenge,address operator);


    /// @notice indicates the window within which DataLayr operator must respond to the SignatoryRecordMinusDumpNumber disclosure challenge 
    uint256 public constant disclosureFraudProofInterval = 7 days;



    constructor(
        DataLayrChallengeUtils _challengeUtils,
        DataLayrDisclosureChallengeFactory _dataLayrDisclosureChallengeFactory
    )  {
        challengeUtils = _challengeUtils;
        dataLayrDisclosureChallengeFactory = _dataLayrDisclosureChallengeFactory;
    }

    /**
     @notice This function is used for opening a forced disclosure challenge against a particular 
             DataLayr operator for a particular dump number.
     */
    /**
     @param headerHash is the hash of summary of the data that was asserted into DataLayr by the disperser during call to initDataStore,
     @param operator is the DataLayr operator against whom forced disclosure challenge is being opened
     @param nonSignerIndex is used for verifying that DataLayr operator is member of the quorum that signed on the dump
     param nonSignerPubkeyHashes is the array of hashes of pubkey of all DataLayr operators that didn't sign for the dump
     param totalEthStakeSigned is the total ETH that has been staked with the DataLayr operators that are in quorum
     param totalEigenStakeSigned is the total Eigen that has been staked with the DataLayr operators that are in quorum
     */
    function forceOperatorToDisclose(
        bytes32 headerHash,
        address operator,
        uint32 operatorIndex,
        uint32 totalOperatorsIndex,
        uint256 nonSignerIndex,
        IDataLayrServiceManager.SignatoryRecordMinusDumpNumber calldata signatoryRecord
    ) public {
        IDataLayrRegistry dlRegistry = IDataLayrRegistry(
            address(repository.registrationManager())
        );
        uint32 chunkNumber;
        uint32 expireTime;

        {
            /**
            Get information on the dataStore for which disperser is being challenged. This dataStore was 
            constructed during call to initDataStore in DataLayr.sol by the disperser.
            */
            (
                uint32 dumpNumber,
                uint32 initTime,
                uint32 storePeriodLength,
                ,
                bool committed
            ) = dataLayr.dataStores(headerHash);

            expireTime = initTime + storePeriodLength;

            // check that disperser had acquire quorum for this dataStore
            require(committed, "Dump is not committed yet");

            /** 
            Check that the information supplied as input for forced disclosure for this particular data 
            dump on DataLayr is correct
            */
            require(
                getDumpNumberSignatureHash(dumpNumber) ==
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

        /**
         @notice check that the challenger is giving enough time to the DataLayr operator for responding to
                 forced disclosure. 
         */
        // todo: need to finalize this.

        /*
        require(
            block.timestamp < expireTime - 600 ||
                (block.timestamp <
                    disclosureForOperator[headerHash][operator].commitTime +
                        2 *
                        disclosureFraudProofInterval &&
                    block.timestamp >
                    disclosureForOperator[headerHash][operator].commitTime +
                        disclosureFraudProofInterval),
            "Must challenge before 10 minutes before expiry or within consecutive disclosure time"
        );
        */

        // check that the DataLayr operator hasn't been challenged yet
        require(
            disclosureForOperator[headerHash][operator].status == 0,
            "Operator is already challenged for dump number"
        );

        // record details of forced disclosure challenge that has been opened
        disclosureForOperator[headerHash][operator] = DisclosureChallenge(
            // the current timestamp when the challenge was created
            uint32(block.timestamp),
            // challenger's address
            msg.sender,
            // address of challenge contract if there is one
            address(0),
            // todo: set degree here
            0,
            // set the status to 1 as forced disclosure challenge has been opened
            1,
            0,
            0,
            bytes32(0),
            chunkNumber,
            0
        );

        emit DisclosureChallengeInit(headerHash, operator);
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
    function respondToDisclosureInit(
        bytes calldata header,
        uint256[4] calldata multireveal,
        bytes calldata poly,
        uint256[4] memory zeroPoly,
        bytes calldata zeroPolyProof
    ) external {
        bytes32 headerHash = keccak256(header);

        // check that DataLayr operator is responding to the forced disclosure challenge period within some window
        /*
        require(
            block.timestamp <
                disclosureForOperator[headerHash][msg.sender].commitTime +
                    disclosureFraudProofInterval,
            "must be in fraud proof period"
        );
        */
        bytes32 data;
        uint256 position;
        // check that it is DataLayr operator who is supposed to respond
        require(
            disclosureForOperator[headerHash][msg.sender].status == 1,
            "Not in operator initial response phase"
        );

        //not so critic: move comments here
        uint48 degree = validateDisclosureResponse(
            disclosureForOperator[headerHash][msg.sender].chunkNumber,
            header,
            multireveal,
            zeroPoly,
            zeroPolyProof
        );

        /*
        degree is the poly length, no need to multiply 32, as it is the size of data in bytes
        require(
            (degree + 1) * 32 == poly.length,
            "Polynomial must have a 256 bit coefficient for each term"
        );
        */

        // check that [zeroPoly.x0, zeroPoly.x1, zeroPoly.y0, zeroPoly.y1] is actually the "chunkNumber" leaf
        // of the zero polynomial Merkle tree

        // update disclosure to record Interpolating poly commitment - [I(s).x, Is(s).y]
        disclosureForOperator[headerHash][msg.sender].x = multireveal[2];
        disclosureForOperator[headerHash][msg.sender].y = multireveal[3];

        // update disclosure to record  hash of interpolating polynomial I_k(x)
        disclosureForOperator[headerHash][msg.sender].polyHash = keccak256(
            poly
        );

        // update disclosure to record degree of the interpolating polynomial I_k(x)
        disclosureForOperator[headerHash][msg.sender].degree = degree;
        disclosureForOperator[headerHash][msg.sender].status = 2;

        emit DisclosureChallengeResponse(headerHash, msg.sender, poly);
    }

    /**
     @notice 
        For simpicity of notation, let the interpolating polynomial I_k(x) for the DataLayr operation k
        be denoted by I(x). Assume the interpolating polynomial is of degree d and its coefficients are 
        c_0, c_1, ...., c_d. 
        
        Then, substituting x = s, we can write:
         I(s) = c_0 + c_1 * s + c_2 * s^2 + c_3 * s^3 + ... + c_d * s^d
              = [c_0 + c_1 * s + ... + c_{d/2} * s^(d/2)] + [c_{d/2 + 1} * s^(d/2 + 1) ... + c_d * s^d]
              =                   coors1(s)               +                        coors2(s)
     */
    /**
     @param headerHash is the hash of summary of the data that was asserted into DataLayr by the disperser during call to initDataStore,
     @param operator is the address of the DataLayr operator
     @param coors this is of the format: [coors1(s).x, coors1(s).y, coors2(s).x, coors2(s).y]
     */
    function initInterpolatingPolynomialFraudProof(
        bytes32 headerHash,
        address operator,
        uint256[4] memory coors
    ) public {
        require(
            disclosureForOperator[headerHash][operator].challenger ==
                msg.sender,
            "Only challenger can call"
        );

        require(
            disclosureForOperator[headerHash][operator].status == 2,
            "Not in post operator response phase"
        );

        // update commit time
        disclosureForOperator[headerHash][operator].commitTime = uint32(
            block.timestamp
        );

        // update status to challenged
        disclosureForOperator[headerHash][operator].status = 3;

        /**
         @notice We need to ensure that the challenge is legitimate. In order to do so, we want coors1(s) and 
                 coors2(s) to be such that:
                                        I(s) != coors1(s) + coors2(s)   
         */
        uint256[2] memory res;

        // doing coors1(s) + coors2(s)
        assembly {
            if iszero(call(not(0), 0x06, 0, coors, 0x80, res, 0x40)) {
                revert(0, 0)
            }
        }

        // checking I(s) != coors1(s) + coors2(s)
        require(
            res[0] != disclosureForOperator[headerHash][operator].x ||
                res[0] != disclosureForOperator[headerHash][operator].y,
            "Cannot commit to same polynomial as the interpolating polynomial"
        );

        // degree has been narrowed down by half every dissection
        uint48 halfDegree = disclosureForOperator[headerHash][operator].degree /
            2;

        // initializing the interaction-style forced disclosure challenge
        address disclosureChallenge = address(
            dataLayrDisclosureChallengeFactory
                .createDataLayrDisclosureChallenge(
                    headerHash,
                    operator,
                    msg.sender,
                    coors[0],
                    coors[1],
                    coors[2],
                    coors[3],
                    halfDegree
                )
        );

        // recording the contract address for interaction-style forced disclosure challenge
        disclosureForOperator[headerHash][operator]
            .challenge = disclosureChallenge;

        emit DisclosureChallengeInteractive(
            headerHash,
            disclosureChallenge,
            operator
        );
    }
    
    /**
     @notice This function is called for settling the forced disclosure challenge.
     */
    /**
     @param headerHash is the hash of summary of the data that was asserted into DataLayr by the disperser during call to initDataStore,
     @param operator is the address of DataLAyr operator
     @param winner representing who is the winner - challenged DataLayr operator or the challenger?  
     */
    // CRITIC: there are some @todo's here
    function resolveDisclosureChallenge(
        bytes32 headerHash,
        address operator,
        bool winner
    ) external {
        if (
            msg.sender == disclosureForOperator[headerHash][operator].challenge
        ) {
            /** 
                the above condition would be called by the forced disclosure challenge contract when the final 
                step of the interactive fraudproof for single monomial has finished
            */
            if (winner) {
                // challenger was wrong, allow for another forced disclosure challenge
                disclosureForOperator[headerHash][operator].status = 0;
                disclosureForOperator[headerHash][operator].commitTime = uint32(
                    block.timestamp
                );

                // @todo give them previous challengers payment
            } else {
                // challeger was correct, reset payment
                disclosureForOperator[headerHash][operator].status = 4;
                // @todo do something
            }
        } else if (
            msg.sender == disclosureForOperator[headerHash][operator].challenger
        ) {
            /** 
                the above condition would be called by the challenger in case if the DataLayr operator doesn't 
                respond in time
             */

            require(
                disclosureForOperator[headerHash][operator].status == 1,
                "Operator is not in initial response phase"
            );
            require(
                block.timestamp >
                    disclosureForOperator[headerHash][operator].commitTime +
                        disclosureFraudProofInterval,
                "Fraud proof period has not passed"
            );

            //slash here
        } else if (msg.sender == operator) {
            /** 
                the above condition would be called by the DataLayr operator in case if the challenger doesn't 
                respond in time
             */

            require(
                disclosureForOperator[headerHash][operator].status == 2,
                "Challenger is not in commitment challenge phase"
            );
            require(
                block.timestamp >
                    disclosureForOperator[headerHash][operator].commitTime +
                        disclosureFraudProofInterval,
                "Fraud proof period has not passed"
            );

            //get challengers payment here
        } else {
            revert(
                "Only the challenge contract, challenger, or operator can call"
            );
        }
    }

    /**
     @notice this function returns the compressed record on the signatures of DataLayr nodes 
             that aren't part of the quorum for this @param _dumpNumber.
     */
    function getDumpNumberSignatureHash(uint32 _dumpNumber)
        public
        view
        returns (bytes32)
    {
        return dumpNumberToSignatureHash[_dumpNumber];
    }




    function validateDisclosureResponse(
        uint256 chunkNumber,
        bytes calldata header,
        uint256[4] calldata multireveal,
        // bytes calldata poly,
        uint256[4] memory zeroPoly,
        bytes calldata zeroPolyProof
    ) public returns(uint48) {
        (
            uint256[2] memory c,
            uint48 degree,
            uint32 numSys,
            uint32 numPar
        ) = challengeUtils.getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(
                header
            );
            // modulus for the underlying field F_q of the elliptic curve
        /*
        degree is the poly length, no need to multiply 32, as it is the size of data in bytes
        require(
            (degree + 1) * 32 == poly.length,
            "Polynomial must have a 256 bit coefficient for each term"
        );
        */

        // check that [zeroPoly.x0, zeroPoly.x1, zeroPoly.y0, zeroPoly.y1] is actually the "chunkNumber" leaf
        // of the zero polynomial Merkle tree

        {
            //deterministic assignment of "y" here
            // @todo
            require(
                Merkle.checkMembership(
                    // leaf
                    keccak256(
                        abi.encodePacked(
                            zeroPoly[0],
                            zeroPoly[1],
                            zeroPoly[2],
                            zeroPoly[3]
                        )
                    ),
                    // index in the Merkle tree
                    challengeUtils.getLeadingCosetIndexFromHighestRootOfUnity(
                        uint32(chunkNumber),
                        numSys,
                        numPar
                    ),
                    // Merkle root hash
                    challengeUtils.getZeroPolyMerkleRoot(degree),
                    // Merkle proof
                    zeroPolyProof
                ),
                "Incorrect zero poly merkle proof"
            );
        }

        /**
         Doing pairing verification  e(Pi(s), Z_k(s)).e(C - I, -g2) == 1
         */
        //get the commitment to the zero polynomial of multireveal degree

        uint256[13] memory pairingInput;


        assembly {
            // extract the proof [Pi(s).x, Pi(s).y]
            mstore(pairingInput, calldataload(36))
            mstore(add(pairingInput, 0x20), calldataload(68))

            // extract the commitment to the zero polynomial: [Z_k(s).x0, Z_k(s).x1, Z_k(s).y0, Z_k(s).y1]
            mstore(add(pairingInput, 0x40), mload(add(zeroPoly, 0x20)))
            mstore(add(pairingInput, 0x60), mload(zeroPoly))
            mstore(add(pairingInput, 0x80), mload(add(zeroPoly, 0x60)))
            mstore(add(pairingInput, 0xA0), mload(add(zeroPoly, 0x40)))

            // extract the polynomial that was committed to by the disperser while initDataStore [C.x, C.y]
            mstore(add(pairingInput, 0xC0), mload(c))
            mstore(add(pairingInput, 0xE0), mload(add(c, 0x20)))

            // extract the commitment to the interpolating polynomial [I_k(s).x, I_k(s).y] and then negate it
            // to get [I_k(s).x, -I_k(s).y]
            mstore(add(pairingInput, 0x100), calldataload(100))
            // obtain -I_k(s).y
            mstore(
                add(pairingInput, 0x120),
                addmod(0, sub(MODULUS, calldataload(132)), MODULUS)
            )
        }

        assembly {
            // overwrite C(s) with C(s) - I(s)

            // @dev using precompiled contract at 0x06 to do point addition on elliptic curve alt_bn128

            if iszero(
                call(
                    not(0),
                    0x06,
                    0,
                    add(pairingInput, 0xC0),
                    0x80,
                    add(pairingInput, 0xC0),
                    0x40
                )
            ) {
                revert(0, 0)
            }
        }

        // check e(pi, z)e(C - I, -g2) == 1
        assembly {
            // store -g2, where g2 is the negation of the generator of group G2
            mstore(add(pairingInput, 0x100), nG2x1)
            mstore(add(pairingInput, 0x120), nG2x0)
            mstore(add(pairingInput, 0x140), nG2y1)
            mstore(add(pairingInput, 0x160), nG2y0)

            // call the precompiled ec2 pairing contract at 0x08
            if iszero(
                call(
                    not(0),
                    0x08,
                    0,
                    pairingInput,
                    0x180,
                    add(pairingInput, 0x180),
                    0x20
                )
            ) {
                revert(0, 0)
            }
        }

        require(pairingInput[12] == 1, "Pairing unsuccessful");
        return degree;
    }



//***HELPER FUNCTIONS***
    function getPolyHash(address operator, bytes32 headerHash)
        public
        view
        returns (bytes32)
    {
        return disclosureForOperator[headerHash][operator].polyHash;
    }



    function NonInteractivePolynomialProof(
        uint256 chunkNumber,
        bytes calldata header,
        uint256[4] calldata multireveal,
        bytes calldata poly,
        uint256[4] memory zeroPoly,
        bytes calldata zeroPolyProof,
        uint256[4] calldata pi
    ) public returns(bool) {

        (
            uint256[2] memory c,
            ,
            ,
        ) = challengeUtils.getDataCommitmentAndMultirevealDegreeAndSymbolBreakdownFromHeader(
                header
            );

        //verify pairing for the commitment to interpolating polynomial
        uint48 dg = validateDisclosureResponse(
            chunkNumber, 
            header, 
            multireveal,
            zeroPoly, 
            zeroPolyProof
        );


        //Calculating r, the point at which to evaluate the interpolating polynomial
        uint256 r = uint(keccak256(poly)) % MODULUS;
        uint256 s = linearPolynomialEvaluation(poly, r);
        bool res = challengeUtils.openPolynomialAtPoint(c, pi, r, s); 

        if (res){
            return true;
        }
        return false;
        
    }

    //evaluates the given polynomial "poly" at value "r" and returns the result
    function linearPolynomialEvaluation(
        bytes calldata poly,
        uint256 r
    ) public returns(uint256){
        uint256 sum;
        uint length = poly.length/32;
        uint256 rPower = 1;
        for (uint i = 0; i < length; i++){
            uint coefficient = uint(bytes32(poly[i:i+32]));
            sum += (coefficient * rPower);
            rPower *= r;
        }   
        return sum; 
    }

        
}