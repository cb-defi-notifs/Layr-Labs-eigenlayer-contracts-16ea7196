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
     * @dev The EigenLayr delegation contract for this DataLayr which primarily used by
     *      delegators to delegate their stake to operators who would serve as DataLayr
     *      nodes and so on. For more details, see EigenLayrDelegation.sol.
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
     *            into DataLayr and is waiting for obtaining quorum of DataLayr nodes to sign,
     *          - asserting the metadata corresponding to the data asserted into DataLayr
     *          - escrow the service fees that DataLayr nodes will receive from the disperser
     *            on account of their service.
     */
    /**
     * @param header is the summary of the data that is being asserted into DataLayr,
     * @param storePeriodLength for which the data has to be stored by the DataLayr nodes,
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

        // increment the counter
        dumpNumber++;

        // record the total service fee that will be paid out for this assertion of data
        dumpNumberToFee[dumpNumber] = fee;

        // recording the expiry time until which the DataLayr nodes, who sign up to
        // part of the quorum, have to store the data
        IDataLayrVoteWeigher(address(repository.voteWeigher())).setLatestTime(
            uint32(block.timestamp) + storePeriodLength
        );

        // escrow the total service fees from the storer to the DataLayr nodes in this contract
        paymentToken.transferFrom(msg.sender, address(this), fee);

        // call DL contract
        dataLayr.initDataStore(
            dumpNumber,
            headerHash,
            totalBytes,
            storePeriodLength
        );
    }

    /**
     * @notice This function is used for
     *          - disperser to notify that signatures on the message, comprising of hash( headerHash ),
     *            from quorum of DataLayr nodes have been obtained,
     *          - check that each of the signatures are valid,
     *          - call the DataLayr contract to check that whether quorum has been achieved or not.
     */
    /**
     * @param data TBA.
     */
    // CRITIC: there is an important todo in this function
    function confirmDataStore(bytes calldata data) external payable {
        // verify the signatures that disperser is claiming to be that of DataLayr nodes
        // who have agreed to be in the quorum
        (
            uint32 dumpNumberToConfirm,
            bytes32 headerHash,
            SignatoryTotals memory signedTotals,
            bytes32 signatoryRecordHash
        ) = checkSignatures(data);

        /**
         * @dev Checks that there is no need for posting a deposit root required for proving
         * the new staking of ETH into settlement layer after the launch of EigenLayr. For
         * more details, see "depositPOSProof" in EigenLayrDeposit.sol.
         */
        require(
            dumpNumberToConfirm % depositRootInterval != 0,
            "Must post a deposit root now"
        );

        // record the compressed information on all the DataLayr nodes who signed
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
     *          - call the DataLayr contract to check that whether quorum has been achieved or not.
     */
    function confirmDataStoreWithPOSt(
        bytes32 depositRoot,
        bytes32 headerHash,
        bytes calldata data
    ) external payable {
        (
            uint32 dumpNumberToConfirm,
            bytes32 depositFerkleHash,
            SignatoryTotals memory signedTotals,
            bytes32 signatoryRecordHash
        ) = checkSignatures(data);

        /**
         * @dev Checks that there is need for posting a deposit root required for proving
         * the new staking of ETH into settlement layer after the launch of EigenLayr. For
         * more details, see "depositPOSProof" in EigenLayrDeposit.sol.
         */
        require(
            dumpNumberToConfirm % depositRootInterval == 0,
            "Shouldn't post a deposit root now"
        );

        // record the compressed information on all the DataLayr nodes who signed
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

    //an operator can commit that they deserve `amount` payment for their service since their last payment to toDumpNumber
    // TODO: collateral
    /**
     * @notice
     */
    function commitPayment(uint32 toDumpNumber, uint120 amount) external {
        // only registered operators can call
        require(
            IDataLayrVoteWeigher(address(repository.voteWeigher()))
                .getOperatorType(msg.sender) != 0,
            "Only registered operators can call this function"
        );



        require(toDumpNumber <= dumpNumber, "Cannot claim future payments");

        // operator puts up collateral which can be slashed in case of wrongful
        // payment claim
        emit log_named_uint("YO", paymentFraudProofCollateral);
        collateralToken.transferFrom(
            msg.sender,
            address(this),
            paymentFraudProofCollateral
        );

        uint32 fromDumpNumber;

        if (operatorToPayment[msg.sender].fromDumpNumber == 0) {
            // this is the first commitment to a payment and thus, it must be claiming
            // payment from when the operator registered

            // get the dumpNumber in the DataLayr when the operator registered
            fromDumpNumber = IDataLayrVoteWeigher(
                address(repository.voteWeigher())
            ).getOperatorFromDumpNumber(msg.sender);

            require(fromDumpNumber < toDumpNumber, "invalid payment range");

            // record the payment information for the operator
            operatorToPayment[msg.sender] = Payment(
                fromDumpNumber,
                toDumpNumber,
                uint32(block.timestamp),
                amount,
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

    // can only call after challenge window
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

    //a fraud prover can challenge a payment to initiate an interactive arbitrum type proof
    //TODO: How much collateral
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

    // function forceDLNToDisclose(
    //     bytes32 headerHash,
    //     uint256 nonSignerIndex,
    //     bytes32[] memory nonSignerPubkeyHashes,
    //     uint256 totalEthStakeSigned,
    //     uint256 totalEigenStakeSigned
    // ) public {
    //     //get the dataStore being challenged
    //     (
    //         uint32 dumpNumber,
    //         uint32 initTime,
    //         uint32 storePeriodLength,
    //         bool commited
    //     ) = dataLayr.dataStores(headerHash);
    //     require(commited, "Dump is not commited yet");
    //     bytes32 stakeHash = IDataLayrVoteWeigher(
    //         address(repository.voteWeigher())
    //     ).getStakesHashUpdateAndCheckIndex(stakeHashIndex, dumpNumber);

    //     //hash stakes and make sure preimage is correct
    //     require(
    //         keccak256(stakes) == stakeHash,
    //         "Stakes provided are inconsistent with hashes"
    //     );
    //     uint256 operatorPointer = 44 * operatorIndex;
    //     //make sure pointer is before total stakes and last persons stake amounts
    //     require(
    //         operatorPointer < stakes.length - 67,
    //         "Cannot point to totals or further"
    //     );
    //     address operator = stakes.toAddress(operatorPointer);
    //     require(
    //         block.timestamp < initTime + storePeriodLength - 600 ||
    //             (block.timestamp <
    //                 disclosureForOperator[headerHash][operator].commitTime +
    //                     2 *
    //                     disclosureFraudProofInterval &&
    //                 block.timestamp >
    //                 disclosureForOperator[headerHash][operator].commitTime +
    //                     disclosureFraudProofInterval),
    //         "Must challenge before 10 minutes before expiry or within consecutive disclosure time"
    //     );
    //     require(
    //         disclosureForOperator[headerHash][operator].status == 0,
    //         "Operator is already challenged for dump number"
    //     );
    //     disclosureForOperator[headerHash][operator] = DisclosureChallenge(
    //         uint32(block.timestamp),
    //         msg.sender, // dumpNumber payment being claimed from
    //         address(0), //address of challenge contract if there is one
    //         0, //TODO: set degree here
    //         1,
    //         0,
    //         0,
    //         bytes32(0)
    //     );
    //     emit DisclosureChallengeInit(headerHash, operator);
    // }

    function respondToDisclosureInit(
        MultiReveal calldata multireveal,
        bytes calldata poly,
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
        (
            uint256[2] memory c,
            uint48 degree
        ) = getDataCommitmentAndMultirevealDegreeFromHeader(header);
        require(
            degree * 32 == poly.length,
            "Polynomial mus have a 256 bit coefficient for each term"
        );
        //get the commitment to the zero polynomial of multireveal degree
        // e(pi, z) = pairing
        uint256[6] memory lhs_coors;
        lhs_coors[0] = multireveal.pi_x;
        lhs_coors[1] = multireveal.pi_y;
        lhs_coors[2] = zeroPolynomialCommitments[degree].x;
        lhs_coors[3] = zeroPolynomialCommitments[degree].y;
        lhs_coors[4] = multireveal.pairing_x;
        lhs_coors[5] = multireveal.pairing_y;
        //get coordinates in memory
        uint256[8] memory rhs_coors;
        rhs_coors[0] = multireveal.i_x;
        rhs_coors[1] = multireveal.i_y;
        rhs_coors[2] = multireveal.c_minus_i_x;
        rhs_coors[3] = multireveal.c_minus_i_y;
        uint256[2] memory i_plus_c_minus_i;
        assembly {
            if iszero(
                call(not(0), 0x06, 0, rhs_coors, 0x80, i_plus_c_minus_i, 0x40)
            ) {
                revert(0, 0)
            }
        }
        require(
            i_plus_c_minus_i[0] == c[0] && i_plus_c_minus_i[1] == c[1],
            "c_minus_i is not correct"
        );
        //TODO: Bowen what is coordinates of H?
        rhs_coors[4] = 1;
        rhs_coors[5] = 1;
        rhs_coors[6] = multireveal.pairing_x;
        rhs_coors[7] = multireveal.pairing_y;
        //e(pi, z) = e(c_minus_i, H)
        assembly {
            //check the lhs paring
            if iszero(call(not(0), 0x07, 0, lhs_coors, 0xC0, 0x0, 0x0)) {
                revert(0, 0)
            }
            //check the rhs paring
            if iszero(
                call(not(0), 0x07, 0, add(rhs_coors, 0x40), 0xC0, 0x0, 0x0)
            ) {
                revert(0, 0)
            }
        }
        //update disclosure to add commitment point, hash of poly, and degree
        disclosureForOperator[headerHash][msg.sender].x = multireveal.i_x;
        disclosureForOperator[headerHash][msg.sender].y = multireveal.i_y;
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
        uint256 x_low,
        uint256 y_low,
        uint256 x_high,
        uint256 y_high
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
        disclosureForOperator[headerHash][operator].commitTime = uint32(
            block.timestamp
        );
        disclosureForOperator[headerHash][operator].status = 3;
        uint256[6] memory coors;
        coors[0] = x_low;
        coors[1] = y_low;
        coors[2] = x_high;
        coors[3] = y_high;
        assembly {
            if iszero(
                call(not(0), 0x06, 0, coors, 0x80, add(coors, 0x80), 0x40)
            ) {
                revert(0, 0)
            }
        }
        require(
            coors[4] != disclosureForOperator[headerHash][operator].x ||
                coors[5] != disclosureForOperator[headerHash][operator].y,
            "Cannot commit to same polynomial as DLN"
        );
        uint48 temp = disclosureForOperator[headerHash][operator].degree / 2;
        disclosureForOperator[headerHash][operator].challenge = address(
            dataLayrDisclosureChallengeFactory
                .createDataLayrDisclosureChallenge(
                    operator,
                    msg.sender,
                    x_low,
                    y_low,
                    x_high,
                    y_high,
                    temp
                )
        );
    }

    function getDataCommitmentAndMultirevealDegreeFromHeader(
        bytes calldata header
    ) public returns (uint256[2] memory, uint48) {
        //TODO: Bowen Implement
        // return x, y coordinate of overall data poly commitment
        // then return degree of multireveal polynomial
        uint256[2] memory point = [uint256(0), uint256(0)];
        return (point, 0);
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

// TODO: @Gautham -- fill this in or delete it?
/*
    function getZeroPolynomialCommitment(uint256 degree, uint256 y)
        internal
        returns (uint256, uint256)
    {
        // calculate y^degree mod p
        bytes memory input;
        uint256 y_to_the_degree;
        assembly {
            mstore(input, 4) //max 4 bytes worth of operators 2^32
            mstore(add(input, 32), 4) //2^32 is the biggest power and smallest root of unity
            mstore(add(input, 64), 32) //bn254's modulus is 254 bits!
            mstore(add(input, 96), shl(224, y)) //y is the base
            mstore(add(input, 100), shl(224, degree)) //degree is the power
            mstore(
                add(input, 104),
                21888242871839275222246405745257275088696311157297823662689037894645226208583
            ) //the modulus of bn254
            if iszero(
                call(not(0), 0x05, 0, input, 0x12, y_to_the_degree, 0x20)
            ) {
                revert(0, 0)
            }
        }
    }
*/

    function getDumpNumberFee(uint32 _dumpNumber)
        public
        view
        returns (uint256)
    {
        return dumpNumberToFee[_dumpNumber];
    }

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
