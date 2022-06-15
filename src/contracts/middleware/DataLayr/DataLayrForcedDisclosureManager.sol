// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrRegistry.sol";
import "../../interfaces/IRepository.sol";
import "../../interfaces/IDataLayr.sol";
import "./DataLayrDisclosureUtils.sol";
import "../../interfaces/IDataLayrServiceManager.sol";

import "ds-test/test.sol";

contract DataLayrForcedDisclosureManager {
    // struct SignatoryRecordMinusDumpNumber {
    //     bytes32[] nonSignerPubkeyHashes;
    //     uint256 totalEthStakeSigned;
    //     uint256 totalEigenStakeSigned;
    // }

    IRepository public repository;
    IDataLayr public dataLayr;
    DataLayrDisclosureUtils public immutable disclosureUtils;

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


    // EVENTS
    /**
     @notice used for notifying that disperser has initiated a forced disclosure challenge.
     */
    event DisclosureChallengeInit(bytes32 headerHash, address operator);
     /**
     @notice used for disclosing the multireveals and coefficients of the associated interpolating polynomial
     */
    event DisclosureChallengeResponse(bytes32 headerHash,address operator,bytes poly);



    constructor(DataLayrDisclosureUtils _disclosureUtils)  {
        disclosureUtils = _disclosureUtils;
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
                disclosureUtils.checkInclusionExclusionInNonSigner(
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
        uint48 degree = disclosureUtils.validateDisclosureResponse(
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



}