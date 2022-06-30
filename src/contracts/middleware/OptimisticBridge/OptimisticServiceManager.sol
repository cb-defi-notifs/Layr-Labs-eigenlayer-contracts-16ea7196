// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../interfaces/IRepository.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/IDelegationTerms.sol";

import "../ServiceManagerStorage.sol";
import "../SignatureChecker.sol";
import "../PaymentManager.sol";
import "../Repository.sol";

import "./nearbridge/NearBridge.sol";

import "../../libraries/BytesLib.sol";
import "../../libraries/Merkle.sol";


import "ds-test/test.sol";

/**
 * @notice This contract is used for:
            - initializing the data store by the disperser
            - confirming the data store by the disperser with inferred aggregated signatures of the quorum
            - doing forced disclosure challenge
            - doing payment challenge
 */
contract OptimisticBridgeServiceManager is
    PaymentManager
    // ,DSTest
{
    INearBridge nearbridge;
    Ed25519 immutable edwards;
    using BytesLib for bytes;

    constructor(
        IEigenLayrDelegation _eigenLayrDelegation,
        IERC20 _paymentToken,
        IERC20 _collateralToken,
        PaymentChallengeFactory _paymentChallengeFactory,
        uint256 _feePerBytePerTime
    ) PaymentManager(_eigenLayrDelegation, _paymentToken, _collateralToken, _paymentChallengeFactory) {
        feePerBytePerTime = _feePerBytePerTime;
    }

    function setRepository(IRepository _repository) public {
        require(address(repository) == address(0), "repository already set");
        repository = _repository;
    }

    function initBridge() public {
        

        nearbridge = NearBridge();
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
     * @param blockNumber for which the confirmation will consult total + operator stake amounts 
     *          -- must not be more than 'BLOCK_STALE_MEASURE' (defined in DataLayr) blocks in past
     */
    function initDataStore(
        bytes calldata headerhash,
        uint32 blockNumber
    ) external payable {
        //bytes32 headerHash = keccak256(header);

        //@TODO: check signatures on the signed header hash 

        // evaluate the total service fees that msg.sender has to put in escrow for paying out
        // the DataLayr nodes for their service
        uint256 fee = 1000 wei;

        // record the total service fee that will be paid out for this assertion of data
        taskNumberToFee[taskNumber] = fee;

        // recording the expiry time until which the DataLayr operators, who sign up to
        // part of the quorum, have to store the data
        // IDataLayrRegistry(address(repository.voteWeigher())).setLatestTime(
        //     uint32(block.timestamp) + storePeriodLength
        // );

        // escrow the total service fees from the disperser to the DataLayr operators in this contract
        paymentToken.transferFrom(msg.sender, address(this), fee);

        // call DataLayr contract
        // dataLayr.initDataStore(
        //     taskNumber,
        //     headerHash,
        //     totalBytes,
        //     storePeriodLength,
        //     blockNumber,
        //     header
        // );

        // increment the counter
        ++taskNumber;
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
             bytes32 headerHash,
             uint48 index of the totalStake corresponding to the taskNumber in the 'totalStakeHistory' array of the DataLayrRegistry
             uint32 numberOfNonSigners,
             uint256[numberOfSigners][4] pubkeys of nonsigners,
             uint32 apkIndex,
             uint256[4] apk,
             uint256[2] sigma
            >
     */
    // CRITIC: there is an important todo in this function
    function confirmDataStore(bytes calldata data, bytes calldata block) external payable {
        // verify the signatures that disperser is claiming to be that of DataLayr operators
        // who have agreed to be in the quorum
        (
            uint32 taskNumberToConfirm, 
            bytes32 headerHash,
            SignatoryTotals memory signedTotals,
            bytes32 signatoryRecordHash
        ) = checkSignatures(data);

        require(taskNumberToConfirm > 0 && taskNumberToConfirm < taskNumber, "Task number is invalid");

        // record the compressed information pertaining to this particular task
        /**
         @notice signatoryRecordHash records pubkey hashes of DataLayr operators who didn't sign
         */
        taskNumberToSignatureHash[taskNumberToConfirm] = signatoryRecordHash;

        //add block 
        nearbridge.addLightClientBlock(block);


        // call DataLayr contract to check whether quorum is satisfied or not and record it
        // dataLayr.confirm(
        //     taskNumberToConfirm,
        //     headerHash,
        //     signedTotals.ethStakeSigned,
        //     signedTotals.eigenStakeSigned,
        //     signedTotals.totalEthStake,
        //     signedTotals.totalEigenStake
        // );
    }
}
