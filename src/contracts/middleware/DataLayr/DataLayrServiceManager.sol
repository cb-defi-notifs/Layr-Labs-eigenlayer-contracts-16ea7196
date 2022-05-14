// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IRepository.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/ProofOfStakingInterfaces.sol";
import "../../interfaces/IDelegationTerms.sol";
import "./DataLayrServiceManagerStorage.sol";
import "./DataLayrDisclosureChallengeFactory.sol";
import "./DataLayrSignatureChecker.sol";
import "../../libraries/BytesLib.sol";
import "../Repository.sol";

import "ds-test/test.sol";

/**
 * @notice
 */
contract DataLayrServiceManager is
    DataLayrSignatureChecker,
    IProofOfStakingOracle
    // ,DSTest
{
    using BytesLib for bytes;
    /**
     * @notice The EigenLayr delegation contract for this DataLayr which is primarily used by
     *      delegators to delegate their stake to operators who would serve as DataLayr
     *      nodes and so on.
     */
    /**
      @dev For more details, see EigenLayrDelegation.sol. 
     */
    IEigenLayrDelegation public immutable eigenLayrDelegation;

    /**
     * @notice factory contract used to deploy new DataLayrPaymentChallenge contracts
     */
    DataLayrPaymentChallengeFactory
        public immutable dataLayrPaymentChallengeFactory;

    /**
     * @notice factory contract used to deploy new DataLayrDisclosureChallenge contracts
     */
    DataLayrDisclosureChallengeFactory
        public immutable dataLayrDisclosureChallengeFactory;

    // EVENTS
    /**
     * @notice used for notifying that disperser has initiated a data assertion into the
     *         DataLayr and is waiting for getting a quorum of DataLayr nodes to sign on it.
     */

    event DisclosureChallengeInit(bytes32 headerHash, address operator);

    event PaymentCommit(
        address operator,
        uint32 fromDumpNumber,
        uint32 toDumpNumber,
        uint256 fee
    );

    event PaymentChallengeInit(address operator, address challenger);

    event PaymentChallengeResolution(address operator, bool operatorWon);

    event PaymentRedemption(address operator, uint256 fee);

    constructor(
        IEigenLayrDelegation _eigenLayrDelegation,
        IERC20 _paymentToken,
        IERC20 _collateralToken,
        uint256 _feePerBytePerTime,
        DataLayrPaymentChallengeFactory _dataLayrPaymentChallengeFactory,
        DataLayrDisclosureChallengeFactory _dataLayrDisclosureChallengeFactory
    ) DataLayrServiceManagerStorage(_paymentToken, _collateralToken) {
        eigenLayrDelegation = _eigenLayrDelegation;
        feePerBytePerTime = _feePerBytePerTime;
        dataLayrPaymentChallengeFactory = _dataLayrPaymentChallengeFactory;
        dataLayrDisclosureChallengeFactory = _dataLayrDisclosureChallengeFactory;
    }

    modifier onlyRepositoryGovernance() {
        require(
            address(repository.timelock()) == msg.sender,
            "only repository governance can call this function"
        );
        _;
    }

    function setRepository(IRepository _repository) public {
        require(address(repository) == address(0), "repository already set");
        repository = _repository;
    }

    /**
     * @notice This function is used for
     *          - notifying in the settlement layer that the disperser has asserted the data
     *            into DataLayr and is waiting for obtaining quorum of DataLayr operators to sign,
     *          - asserting the metadata corresponding to the data asserted into DataLayr
     *          - escrow the service fees that DataLayr operators will receive from the disperser
     *            on account of their service.
     */
    /**
     * @param header is the summary of the data that is being asserted into DataLayr,
     * @param storePeriodLength for which the data has to be stored by the DataLayr operators,
     * @param totalBytes  is the size of the data ,
     */
    function initDataStore(
        bytes calldata header,
        uint32 totalBytes,
        uint32 storePeriodLength
    ) external payable {
        bytes32 headerHash = keccak256(header);

        require(totalBytes > 32, "Can't store less than 33 bytes");

        require(storePeriodLength > 60, "store for more than a minute");

        require(storePeriodLength < 604800, "store for less than 7 days");

        //TODO: mechanism to change this?
        require(totalBytes <= 4e9, "store of more than 4 GB");

        // evaluate the total service fees that msg.sender has to put in escrow for paying out
        // the DataLayr nodes for their service
        uint256 fee = (totalBytes * feePerBytePerTime) * storePeriodLength;

        // record the total service fee that will be paid out for this assertion of data
        dumpNumberToFee[dumpNumber] = fee;

        // recording the expiry time until which the DataLayr operators, who sign up to
        // part of the quorum, have to store the data
        IDataLayrRegistry(address(repository.voteWeigher())).setLatestTime(
            uint32(block.timestamp) + storePeriodLength
        );

        // escrow the total service fees from the disperser to the DataLayr operators in this contract
        paymentToken.transferFrom(msg.sender, address(this), fee);

        // call DataLayr contract
        dataLayr.initDataStore(
            dumpNumber,
            headerHash,
            totalBytes,
            storePeriodLength
        );

        // increment the counter
        dumpNumber++;
    }

    /**
     * @notice This function is used for
     *          - disperser to notify that signatures on the message, comprising of hash( headerHash ),
     *            from quorum of DataLayr nodes have been obtained,
     *          - check that each of the signatures are valid,
     *          - call the DataLayr contract to check that whether quorum has been achieved or not.
     */
    /** 
     @param data is of the format:
            <
             uint32 dumpNumber,
             bytes32 headerHash,
             uint48 index of the totalStake corresponding to the dumpNumber in the 'totalStakeHistory' array of the DataLayrRegistry
             uint32 numberOfNonSigners,
             uint256[numberOfSigners][4] pubkeys of nonsigners,
             uint32 apkIndex,
             uint256[4] apk,
             uint256[2] sigma
            >
     */
    // CRITIC: there is an important todo in this function
    function confirmDataStore(bytes calldata data) external payable {
        // verify the signatures that disperser is claiming to be that of DataLayr operators
        // who have agreed to be in the quorum
        (
            uint32 dumpNumberToConfirm,
            bytes32 headerHash,
            SignatoryTotals memory signedTotals,
            bytes32 signatoryRecordHash
        ) = checkSignatures(data);

        /**
         * @notice checks that there is no need for posting a deposit root required for proving
         * the new staking of ETH into Ethereum.
         */
        /**
         @dev for more details, see "depositPOSProof" in EigenLayrDeposit.sol.
         */
        require(
            dumpNumberToConfirm % depositRootInterval != 0,
            "Must post a deposit root now"
        );

        // record the compressed information pertaining to this particular dump
        /**
         @notice signatoryRecordHash records pubkey hashes of DataLayr operators who didn't sign
         */
        dumpNumberToSignatureHash[dumpNumberToConfirm] = signatoryRecordHash;

        // call DataLayr contract to check whether quorum is satisfied or not and record it
        dataLayr.confirm(
            dumpNumberToConfirm,
            headerHash,
            signedTotals.ethStakeSigned,
            signedTotals.eigenStakeSigned,
            signedTotals.totalEthStake,
            signedTotals.totalEigenStake
        );
    }

    /**
     * @notice This function is used when the enshrined DataLayr is used to update the POSt hash
     *         along with the regular assertion of data into the DataLayr by the disperser. This
     *         function enables
     *          - disperser to notify that signatures, comprising of hash(depositRoot || headerHash),
     *            from quorum of DataLayr nodes have been obtained,
     *          - check that each of the signatures are valid,
     *          - store the POSt hash, given by depositRoot,
     *          - call the DataLayr contract to check  whether quorum has been achieved or not.
     */
    function confirmDataStoreWithPOSt(
        bytes32 depositRoot,
        bytes32 headerHash,
        bytes calldata data
    ) external payable {
        // verify the signatures that disperser is claiming to be that of DataLayr operators
        // who have agreed to be in the quorum
        (
            uint32 dumpNumberToConfirm,
            bytes32 depositFerkleHash,
            SignatoryTotals memory signedTotals,
            bytes32 signatoryRecordHash
        ) = checkSignatures(data);

        /**
          @notice checks that there is need for posting a deposit root required for proving
          the new staking of ETH into Ethereum. 
         */
        /**
          @dev for more details, see "depositPOSProof" in EigenLayrDeposit.sol.
         */
        require(
            dumpNumberToConfirm % depositRootInterval == 0,
            "Shouldn't post a deposit root now"
        );

        // record the compressed information on all the DataLayr nodes who signed
        /**
         @notice signatoryRecordHash records pubkey hashes of DataLayr operators who didn't sign
         */
        dumpNumberToSignatureHash[dumpNumberToConfirm] = signatoryRecordHash;

        /**
         * when posting a deposit root, DataLayr nodes will sign hash(depositRoot || headerHash)
         * instead of the usual headerHash, so the submitter must specify the preimage
         */
        require(
            keccak256(abi.encodePacked(depositRoot, headerHash)) ==
                depositFerkleHash,
            "Ferkle or deposit root is incorrect"
        );

        // record the deposit root (POSt hash)
        depositRoots[block.number] = depositRoot;

        // call DataLayr contract to check whether quorum is satisfied or not and record it
        dataLayr.confirm(
            dumpNumberToConfirm,
            headerHash,
            signedTotals.ethStakeSigned,
            signedTotals.eigenStakeSigned,
            signedTotals.totalEthStake,
            signedTotals.totalEigenStake
        );
    }

    // TODO: collateral
    /**
     @notice This is used by a DataLayr operator to make claim on the @param amount that they deserve 
             for their service since their last payment until @param toDumpNumber  
     **/
    function commitPayment(uint32 toDumpNumber, uint120 amount) external {
        // only registered DataLayr operators can call
        require(
            IDataLayrRegistry(address(repository.voteWeigher()))
                .getOperatorType(msg.sender) != 0,
            "Only registered operators can call this function"
        );

        require(toDumpNumber <= dumpNumber, "Cannot claim future payments");

        // operator puts up collateral which can be slashed in case of wrongful payment claim
        collateralToken.transferFrom(
            msg.sender,
            address(this),
            paymentFraudProofCollateral
        );

        /**
         @notice recording payment claims for the DataLayr operators
         */
        uint32 fromDumpNumber;

        // for the special case of this being the first payment that is being claimed by the DataLayr operator;
        /**
         @notice this special case also implies that the DataLayr operator must be claiming payment from 
                 when the operator registered.   
         */
        if (operatorToPayment[msg.sender].fromDumpNumber == 0) {
            // get the dumpNumber when the DataLayr operator registered
            fromDumpNumber = IDataLayrRegistry(
                address(repository.voteWeigher())
            ).getOperatorFromDumpNumber(msg.sender);

            require(fromDumpNumber < toDumpNumber, "invalid payment range");

            // record the payment information pertaining to the operator
            operatorToPayment[msg.sender] = Payment(
                fromDumpNumber,
                toDumpNumber,
                uint32(block.timestamp),
                amount,
                // setting to 0 to indicate commitment to payment claim
                0,
                paymentFraudProofCollateral
            );

            return;
        }

        // can only claim for a payment after redeeming the last payment
        require(
            operatorToPayment[msg.sender].status == 1,
            "Require last payment is redeemed"
        );

        // you have to redeem starting from the last time redeemed up to
        fromDumpNumber = operatorToPayment[msg.sender].toDumpNumber;

        require(fromDumpNumber < toDumpNumber, "invalid payment range");

        // update the record for the commitment to payment made by the operator
        operatorToPayment[msg.sender] = Payment(
            fromDumpNumber,
            toDumpNumber,
            uint32(block.timestamp),
            amount,
            0,
            paymentFraudProofCollateral
        );

        emit PaymentCommit(msg.sender, fromDumpNumber, toDumpNumber, amount);
    }

    /**
     @notice This function can only be called after the challenge window for the payment claim has completed.
     */
    function redeemPayment() external {
        require(
            block.timestamp >
                operatorToPayment[msg.sender].commitTime +
                    paymentFraudProofInterval &&
                operatorToPayment[msg.sender].status == 0,
            "Still eligible for fraud proofs"
        );

        // update the status to show that operator's payment is getting redeemed
        operatorToPayment[msg.sender].status = 1;

        // transfer back the collateral to the operator as there was no successful
        // challenge to the payment commitment made by the operator.
        collateralToken.transfer(
            msg.sender,
            operatorToPayment[msg.sender].collateral
        );

        ///look up payment amount and delegation terms address for the msg.sender
        uint256 amount = operatorToPayment[msg.sender].amount;
        IDelegationTerms dt = eigenLayrDelegation.getDelegationTerms(
            msg.sender
        );

        // i.e. if operator is not a 'self operator'
        if (address(dt) != address(0)) {
            // transfer the amount due in the payment claim of the operator to its delegation
            // terms contract, where the delegators can withdraw their rewards.
            paymentToken.transfer(address(dt), amount);

            // inform the DelegationTerms contract of the payment, which would determine
            // the rewards operator and its delegators are eligible for
            dt.payForService(paymentToken, amount);

            // i.e. if the operator *is* a 'self operator'
        } else {
            //simply transfer the payment amount in this case
            paymentToken.transfer(msg.sender, amount);
        }

        emit PaymentRedemption(msg.sender, amount);
    }

    //
    //TODO: How much collateral
    /**
     @notice This function would be called by a fraud prover to challenge a payment 
             by initiating an interactive type proof
     **/
    /**
     @param operator is the DataLayr operator against whose payment claim the fraud proof is being made
     @param amount1 is the reward amount the challenger in that round claims is for the first half of dumps
     @param amount2 is the reward amount the challenger in that round claims is for the second half of dumps
     **/ 
    function challengePaymentInit(
        address operator,
        uint120 amount1,
        uint120 amount2
    ) external {
        require(
            block.timestamp <
                operatorToPayment[operator].commitTime +
                    paymentFraudProofInterval &&
                operatorToPayment[operator].status == 0,
            "Fraud proof interval has passed"
        );

        // deploy new challenge contract
        address challengeContract = dataLayrPaymentChallengeFactory
            .createDataLayrPaymentChallenge(
                operator,
                msg.sender,
                address(this),
                operatorToPayment[operator].fromDumpNumber,
                operatorToPayment[operator].toDumpNumber,
                amount1,
                amount2
            );
        //move collateral over
        uint256 collateral = operatorToPayment[operator].collateral;
        collateralToken.transferFrom(msg.sender, address(this), collateral);
        //update payment
        operatorToPayment[operator].status = 2;
        operatorToPayment[operator].commitTime = uint32(block.timestamp);
        operatorToPaymentChallenge[operator] = challengeContract;
        emit PaymentChallengeInit(operator, msg.sender);
    }

    function resolvePaymentChallenge(address operator, bool winner) external {
        require(
            msg.sender == operatorToPaymentChallenge[operator],
            "Only the payment challenge contract can call"
        );
        if (winner) {
            // operator was correct, allow for another challenge
            operatorToPayment[operator].status = 0;
            operatorToPayment[operator].commitTime = uint32(block.timestamp);
            //give them previous challengers collateral
            collateralToken.transfer(
                operator,
                operatorToPayment[operator].collateral
            );
            emit PaymentChallengeResolution(operator, true);
        } else {
            // challeger was correct, reset payment
            operatorToPayment[operator].status = 1;
            //give them their collateral and the operators
            collateralToken.transfer(
                operator,
                2 * operatorToPayment[operator].collateral
            );
            emit PaymentChallengeResolution(operator, false);
        }
    }


    /**
     @notice 
     */
    /**
     @param headerHash 
     */
    function forceOperatorToDisclose(
        bytes32 headerHash,
        address operator,
        uint256 nonSignerIndex,
        bytes32[] calldata nonSignerPubkeyHashes,
        uint256 totalEthStakeSigned,
        uint256 totalEigenStakeSigned
    ) public {
        /**
         Get information on the dataStore for which disperser is being challenged. This dataStore was 
         constructed during call to initDataStore in DataLayr.sol by the disperser.
         */
        (
            uint32 dumpNumber,
            uint32 initTime,
            uint32 storePeriodLength,
            bool commited
        ) = dataLayr.dataStores(headerHash);

        // check that disperser had acquire quorum for this dataStore
        require(commited, "Dump is not commited yet");



        /** 
         Check that the information supplied as input for forced disclosure for this particular data 
         dump on DataLayr is correct
         */
        require(
            getDumpNumberSignatureHash(dumpNumber) ==
                keccak256(
                    abi.encodePacked(
                        dumpNumber,
                        nonSignerPubkeyHashes,
                        totalEthStakeSigned,
                        totalEigenStakeSigned
                    )
                ),
            "Sig record does not match hash"
        );



        /**
         Check that the DataLayr operator against whom forced disclosure is being initiated, was
         actually part of the quorum for the @param dumpNumber
         */        
        {
            IDataLayrRegistry dlvw = IDataLayrRegistry(
                address(repository.registrationManager())
            );

            // get the pubkey hash of the DataLayr operator
            bytes32 operatorPubkeyHash = dlvw.getOperatorPubkeyHash(operator);


            
            /** 
              @notice The burden of responsibility lies with the challenger to show that the DataLayr operator 
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
            // check that uint256(nspkh[index]) <  uint256(operatorPubkeyHash) 
            require(
                uint256(nonSignerPubkeyHashes[nonSignerIndex]) <
                    uint256(operatorPubkeyHash) ||
                    (nonSignerIndex == 0 &&
                        uint256(nonSignerPubkeyHashes[0]) >
                        uint256(operatorPubkeyHash)),
                "Wrong index"
            );

            if (nonSignerIndex != nonSignerPubkeyHashes.length - 1) {
                //require that the index+1 is before where operatorpubkey hash would be
                require(
                    uint256(nonSignerPubkeyHashes[nonSignerIndex + 1]) >
                        uint256(operatorPubkeyHash),
                    "Wrong index"
                );
            }
        }
        require(
            block.timestamp < initTime + storePeriodLength - 600 ||
                (block.timestamp <
                    disclosureForOperator[headerHash][operator].commitTime +
                        2 *
                        disclosureFraudProofInterval &&
                    block.timestamp >
                    disclosureForOperator[headerHash][operator].commitTime +
                        disclosureFraudProofInterval),
            "Must challenge before 10 minutes before expiry or within consecutive disclosure time"
        );
        require(
            disclosureForOperator[headerHash][operator].status == 0,
            "Operator is already challenged for dump number"
        );
        disclosureForOperator[headerHash][operator] = DisclosureChallenge(
            uint32(block.timestamp),
            msg.sender, // dumpNumber payment being claimed from
            address(0), //address of challenge contract if there is one
            0, //TODO: set degree here
            1,
            0,
            0,
            bytes32(0)
        );
        emit DisclosureChallengeInit(headerHash, operator);
    }

    function respondToDisclosureInit(
        uint256[4] calldata multireveal,
        bytes calldata poly,
        uint256[4] memory zeroPoly,
        bytes calldata zeroPolyProof,
        bytes calldata header
    ) external {
        bytes32 headerHash = keccak256(header);
        require(
            block.timestamp <
                disclosureForOperator[headerHash][msg.sender].commitTime +
                    disclosureFraudProofInterval,
            "must be in fraud proof period"
        );
        require(
            disclosureForOperator[headerHash][msg.sender].status == 1,
            "Not in operator initial response phase"
        );

        //get the commitment to the entire data polynomial, and the degree of the polynomial itself
        (
            uint256[2] memory c,
            uint48 degree
        ) = getDataCommitmentAndMultirevealDegreeFromHeader(header);
        require(
            (degree + 1) * 32 == poly.length,
            "Polynomial must have a 256 bit coefficient for each term"
        );

        //deterministic assignment of "y" here
        uint256 chunkNumber = 0; //f(operator, header);
        //prove the zero polynomial commitment from here
        require(
            checkMembership(
                keccak256(
                    abi.encodePacked(
                        zeroPoly[0],
                        zeroPoly[1],
                        zeroPoly[2],
                        zeroPoly[3]
                    )
                ),
                chunkNumber,
                zeroPolynomialCommitmentMerlkeRoots[degree],
                zeroPolyProof
            ),
            "Incorrect zero poly merkle proof"
        );

        //get the commitment to the zero polynomial of multireveal degree
        // e(pi, z)e(C - I, -g2) == 1
        uint256[12] memory pairingInput;
        assembly {
            //set pi
            mstore(pairingInput, mload(multireveal))
            mstore(add(pairingInput, 0x20), mload(add(multireveal, 0x20)))
            // set z
            mstore(add(pairingInput, 0x40), mload(zeroPoly))
            mstore(add(pairingInput, 0x60), mload(add(zeroPoly, 0x20)))
            mstore(add(pairingInput, 0x80), mload(add(zeroPoly, 0x40)))
            mstore(add(pairingInput, 0xA0), mload(add(zeroPoly, 0x60)))
            //set C
            mstore(add(pairingInput, 0xC0), mload(c))
            mstore(add(pairingInput, 0xE0), mload(add(c, 0x20)))
            //set -I
            mstore(add(pairingInput, 0x100), mload(add(multireveal, 0x40)))
            //-I.y to get -I
            mstore(
                add(pairingInput, 0x120),
                addmod(0, sub(MODULUS, mload(add(multireveal, 0x60))), MODULUS)
            )
        }
        assembly {
            //overwrite C with C-I
            if iszero(
                call(
                    not(0),
                    0x06,
                    0,
                    add(pairingInput, 0x100),
                    0x80,
                    add(pairingInput, 0x100),
                    0x40
                )
            ) {
                revert(0, 0)
            }
        }
        // e(pi, z)e(C - I, -g2) == 1
        assembly {
            //store -g2
            mstore(add(pairingInput, 0x100), nG2x1)
            mstore(add(pairingInput, 0x120), nG2x0)
            mstore(add(pairingInput, 0x140), nG2y1)
            mstore(add(pairingInput, 0x160), nG2y0)
            //check the lhs paring
            if iszero(
                call(not(0), 0x08, 0, pairingInput, 0x180, pairingInput, 0x20)
            ) {
                revert(0, 0)
            }
        }

        require(pairingInput[0] == 1, "Pairing unsuccessful");

        //update disclosure to add commitment point, hash of poly, and degree
        disclosureForOperator[headerHash][msg.sender].x = multireveal[0];
        disclosureForOperator[headerHash][msg.sender].y = multireveal[1];
        disclosureForOperator[headerHash][msg.sender].polyHash = keccak256(
            poly
        );
        disclosureForOperator[headerHash][msg.sender].commitTime = uint32(
            block.timestamp
        );
        disclosureForOperator[headerHash][msg.sender].status = 2;
        disclosureForOperator[headerHash][msg.sender].degree = degree;
    }

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
        //update commit time
        disclosureForOperator[headerHash][operator].commitTime = uint32(
            block.timestamp
        );
        // update status to challenged
        disclosureForOperator[headerHash][operator].status = 3;
        // make sure the dissection is not commiting to the same polynomial as the DLN
        uint256[2] memory res;

        assembly {
            if iszero(call(not(0), 0x06, 0, coors, 0x80, res, 0x40)) {
                revert(0, 0)
            }
        }
        require(
            res[0] != disclosureForOperator[headerHash][operator].x ||
                res[0] != disclosureForOperator[headerHash][operator].y,
            "Cannot commit to same polynomial as DLN"
        );
        //the degree has been narrowed down by half every dissection
        uint48 halfDegree = disclosureForOperator[headerHash][operator].degree /
            2;
        disclosureForOperator[headerHash][operator].challenge = address(
            dataLayrDisclosureChallengeFactory
                .createDataLayrDisclosureChallenge(
                    operator,
                    msg.sender,
                    coors[0],
                    coors[1],
                    coors[2],
                    coors[3],
                    halfDegree
                )
        );
    }

    function getDataCommitmentAndMultirevealDegreeFromHeader(
        // bytes calldata header
        bytes calldata
    ) public returns (uint256[2] memory, uint48) {
        //TODO: Bowen Implement
        // return x, y coordinate of overall data poly commitment
        // then return degree of multireveal polynomial
        uint256[2] memory point = [uint256(0), uint256(0)];
        return (point, 0);
    }

    //copied from
    function checkMembership(
        bytes32 leaf,
        uint256 index,
        bytes32 rootHash,
        bytes memory proof
    ) internal pure returns (bool) {
        require(proof.length % 32 == 0, "Invalid proof length");
        uint256 proofHeight = proof.length / 32;
        // Proof of size n means, height of the tree is n+1.
        // In a tree of height n+1, max #leafs possible is 2 ^ n
        require(index < 2**proofHeight, "Leaf index is too big");

        bytes32 proofElement;
        bytes32 computedHash = leaf;
        for (uint256 i = 32; i <= proof.length; i += 32) {
            assembly {
                proofElement := mload(add(proof, i))
            }

            if (index % 2 == 0) {
                computedHash = keccak256(
                    abi.encodePacked(computedHash, proofElement)
                );
            } else {
                computedHash = keccak256(
                    abi.encodePacked(proofElement, computedHash)
                );
            }

            index = index / 2;
        }
        return computedHash == rootHash;
    }

    function resolveDisclosureChallenge(
        bytes32 headerHash,
        address operator,
        bool winner
    ) external {
        if (
            msg.sender == disclosureForOperator[headerHash][operator].challenge
        ) {
            if (winner) {
                // operator was correct, allow for another challenge
                disclosureForOperator[headerHash][operator].status = 0;
                operatorToPayment[operator].commitTime = uint32(
                    block.timestamp
                );
                //give them previous challengers payment
            } else {
                // challeger was correct, reset payment
                disclosureForOperator[headerHash][operator].status = 4;
                //do something
            }
        } else if (
            msg.sender == disclosureForOperator[headerHash][operator].challenger
        ) {
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

    function getDumpNumberFee(uint32 _dumpNumber)
        public
        view
        returns (uint256)
    {
        return dumpNumberToFee[_dumpNumber];
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



    function getPaymentCollateral(address operator)
        public
        view
        returns (uint256)
    {
        return operatorToPayment[operator].collateral;
    }

    function getDepositRoot(uint256 blockNumber) public view returns (bytes32) {
        return depositRoots[blockNumber];
    }

    function getPolyHash(address operator, bytes32 headerHash)
        public
        view
        returns (bytes32)
    {
        return disclosureForOperator[headerHash][operator].polyHash;
    }

    function setFeePerBytePerTime(uint256 _feePerBytePerTime)
        public
        onlyRepositoryGovernance
    {
        feePerBytePerTime = _feePerBytePerTime;
    }

    function setPaymentFraudProofCollateral(
        uint256 _paymentFraudProofCollateral
    ) public onlyRepositoryGovernance {
        paymentFraudProofCollateral = _paymentFraudProofCollateral;
    }

    function setDataLayr(IDataLayr _dataLayr) public {
        require(
            (address(dataLayr) == address(0)) ||
                (address(repository.timelock()) == msg.sender),
            "only repository governance can call this function, or DL must not be initialized"
        );
        dataLayr = _dataLayr;
    }

    /// @notice returns the time when the serviceObject, associated with serviceObjectHash, was created
    function getServiceObjectCreationTime(bytes32 serviceObjectHash)
        public
        view
        returns (uint256)
    {
        (, uint32 initTime, , ) = dataLayr.dataStores(serviceObjectHash);
        uint256 timeCreated = uint256(initTime);
        if (timeCreated != 0) {
            return timeCreated;
        } else {
            return type(uint256).max;
        }
    }

    /// @notice returns the time when the serviceObject, associated with serviceObjectHash, will expire
    function getServiceObjectExpiry(bytes32 serviceObjectHash)
        external
        view
        returns (uint256)
    {
        (, uint32 initTime, uint32 storePeriodLength, ) = dataLayr.dataStores(
            serviceObjectHash
        );
        uint256 timeCreated = uint256(initTime);
        if (timeCreated != 0) {
            return (timeCreated + storePeriodLength);
        } else {
            return type(uint256).max;
        }
    }

    /* function removed for now since it tries to modify an immutable variable
    function setPaymentToken(
        IERC20 _paymentToken
    ) public onlyRepositoryGovernance {
        paymentToken = _paymentToken;
    }
*/
}
