// // // SPDX-License-Identifier: UNLICENSED
// // pragma solidity ^0.8.9;

// // import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// // import "../../interfaces/IRepository.sol";
// // import "../../interfaces/IEigenLayrDelegation.sol";
// // import "../../interfaces/IDelegationTerms.sol";

// // import "../ServiceManagerStorage.sol";
// // import "../SignatureChecker.sol";
// // import "../PaymentManager.sol";
// // import "../Repository.sol";

// // import "./nearbridge/NearBridge.sol";

// // import "../../libraries/BytesLib.sol";
// // import "../../libraries/Merkle.sol";


// // import "ds-test/test.sol";

// // /**
// //  * @notice This contract is used for:
// //             - initializing the data store by the disperser
// //             - confirming the data store by the disperser with inferred aggregated signatures of the quorum
// //             - doing forced disclosure challenge
// //             - doing payment challenge
// //  */
// // contract OptimisticBridgeServiceManager is
// //     PaymentManager
// //     // ,DSTest
// // {
// //     INearBridge nearbridge;
// //     Ed25519 immutable edwards;

// //     uint32 currentTaskNumber = 0;

// //     struct BridgeTransfer {
// //         uint32 taskNumber;
// //         uint32 initTime;
// //     }

// //     mapping(bytes32 => BridgeTransfer) bridgeTransferHash;

// //     using BytesLib for bytes;


// //     constructor(
// //         IEigenLayrDelegation _eigenLayrDelegation,
// //         IERC20 _paymentToken,
// //         IERC20 _collateralToken,
// //         PaymentChallengeFactory _paymentChallengeFactory,
// //         uint256 _feePerBytePerTime
// //     ) PaymentManager(_eigenLayrDelegation, _paymentToken, _collateralToken, _paymentChallengeFactory) {
// //         feePerBytePerTime = _feePerBytePerTime;
// //     }

// //     function setRepository(IRepository _repository) public {
// //         require(address(repository) == address(0), "repository already set");
// //         repository = _repository;
// //     }

// //     function initBridge() public {
// //         nearbridge = NearBridge();
// //     }


// //     /**
// //      * @param headerHash is the signed header from the Near blockchain
// //      */
// //     function initBridgeTransfer(
// //         bytes calldata headerhash
// //     ) external payable {

// //         // evaluate the total service fees that msg.sender has to put in escrow for paying out
// //         // the DataLayr nodes for their service
// //         uint256 fee = 1000 wei;

// //         // record the total service fee that will be paid out for this assertion of data
// //         taskNumberToFee[taskNumber] = fee;


// //         // escrow the total service fees from the disperser to the DataLayr operators in this contract
// //         paymentToken.transferFrom(msg.sender, address(this), fee);


// //         uint32 initTime = uint32(block.timestamp);
// //         //record headerhash
// //         bridgeTransferHash[headerhash] = BridgeTransfer(
// //             taskNumber,
// //             initTime
// //         );

// //         // increment the counter
// //         ++taskNumber;
// //     }

// //     /**
// //      * @notice This function is used for
// //      */
// //     /** 
// //      @param data is of the format:
// //      @param header

// //      */

// //     function confirmBridgeTransfer(bytes calldata data, bytes calldata header) external payable {
        

// //         // verify the signatures of the DataLayr operators
// //         (
// //             uint32 taskNumberToConfirm, 
// //             bytes32 headerHash,
// //             SignatoryTotals memory signedTotals,
// //             bytes32 signatoryRecordHash
// //         ) = checkSignatures(data);

// //         require(keccak256(abi.encodePacked(header)) == headerHash, "provided header is incorrect");

// //         require(taskNumberToConfirm > 0 && taskNumberToConfirm < currentTaskNumber, "Task number is invalid");

// //         uint32 taskNumber = bridgeTransferHash[headerHash].taskNumber;

// //         require(taskNumber == taskNumberToConfirm, "task number does not match record for that header");
// //         // record the compressed information pertaining to this particular task
// //         /**
// //          @notice signatoryRecordHash records pubkey hashes of DataLayr operators who didn't sign
// //          */
// //         taskNumberToSignatureHash[taskNumberToConfirm] = signatoryRecordHash;

//         require(taskNumber == taskNumberToConfirm, "task number does not match record for that header");
//         // record the compressed information pertaining to this particular task
//         /**
//          @notice signatoryRecordHash records pubkey hashes of DataLayr operators who didn't sign
//          */
//         taskNumberToSignatureHash[taskNumberToConfirm] = signatoryRecordHash;

//         //add header 
//         nearbridge.addLightClientBlock(header);
//     }


//     function challengeBridge() external payable {
        
//     }
// }
