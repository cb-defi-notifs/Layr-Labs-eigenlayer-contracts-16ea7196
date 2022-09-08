// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/IECDSARegistry.sol";
import "../libraries/BytesLib.sol";
import "../permissions/RepositoryAccess.sol";

import "forge-std/Test.sol";

abstract contract ECDSASignatureChecker is
    RepositoryAccess
    // ,DSTest
{
    using BytesLib for bytes;
    struct SignatoryTotals {
        //total eth stake of the signatories
        uint256 ethStakeSigned;
        //total eigen stake of the signatories
        uint256 eigenStakeSigned;
        uint256 totalEthStake;
        uint256 totalEigenStake;
    }

    struct SignatureWithInfo {
        bytes32 r;
        bytes32 vs;
        address signatory;
        uint32 stakesIndexLocation;
    }

    uint256 internal constant START_OF_STAKES_BYTE_LOCATION = 438;
    uint256 internal constant TWENTY_BYTE_MASK = 0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    /** 
     @dev This calldata is of the format:
            <
             bytes32 headerHash,
             uint48 index of the stakeHash corresponding to the dataStoreId in the 'stakeHashes' array of the ECDSARegistry,
             uint32 blockNumber,
             uint32 dataStoreId,
             uint32 numberofSigners,
             uint256 stakesLength,
             bytes stakes,
             bytes SignatureWithInfos (number of SignatureWithInfo provided here is equal to numberOfSigners)

             stakes layout:
             packed tuple of address, uint96, uint96
                 the uint96's are the ETH and EIGEN stake of the signatory (address)
             with last 24 bytes storing the ETH and EIGEN totals
            >
     */
    //NOTE: this assumes length 64 signatures
    function checkSignatures(bytes calldata data)
        external
        returns (
            uint32 taskNumberToConfirm,
            bytes32 taskHash,
            SignatoryTotals memory signedTotals,
            bytes32 compressedSignatoryRecord
        )
    {
        //temporary variable used to hold various numbers
        uint256 placeholder;

        assembly {
            // get the 32 bytes immediately after the function signature and length + position encoding of bytes
            // calldata type, which represents the taskHash for which disperser is calling checkSignatures
            taskHash := calldataload(356)

            // get the 6 bytes immediately after the above, which represent the
            // index of the stakeHash in the 'stakeHashes' array
            placeholder := shr(208, calldataload(388))
        }


        // fetch the taskNumber to confirm and block number to use for stakes from the middleware contract
        uint32 blockNumberFromTaskHash;
        assembly {
            blockNumberFromTaskHash := shr(224,calldataload(394))
        }

        // obtain registry contract for fetching the stakeHash
        IECDSARegistry registry = IECDSARegistry(address(repository.registry()));
        // fetch the stakeHash
        bytes32 stakeHash = registry.getCorrectStakeHash(placeholder, blockNumberFromTaskHash);

        uint32 numberOfSigners;
        uint256 stakesLength;
        assembly {
            // get the 4 bytes immediately after the above, which represent the
            // number of operators that have signed
            numberOfSigners := shr(224, calldataload(402))
            // get the next 32 bytes, specifying the length of the stakes object
            stakesLength := calldataload(406)
        }

        bytes32 signedHash = ECDSA.toEthSignedMessageHash(taskHash);

        // load stakes into memory and verify integrity of stake hash
        bytes memory stakes = data.slice(START_OF_STAKES_BYTE_LOCATION, stakesLength);

        require(
            keccak256(stakes) == stakeHash,
            "provided stakes are incorrect"
        );

        // we have read (356 + 32 + 6 + 4 + 4 + 4 + 32) = 438 bytes of calldata so far
        // set pointer equal to end of stakes object (*start* of SigWInfos)
        uint256 pointer = START_OF_STAKES_BYTE_LOCATION;

        assembly {
            //fetch the totalEthStake value and store it in memory
            mstore(
                //signedTotals.totalEthStake location
                add(signedTotals, 64),
                //right-shift by 160 to get just the 96 bits we want
                shr(
                    160,
                    //load data beginning 24 bytes before the end of the 'stakes' object (this is where totalEthStake begins)
                    calldataload(
                        sub(pointer, 24)
                    )                 
                )
            )
            //fetch the totalEigenStake value and store it in memory
            mstore(
                //signedTotals.totalEigenStake location
                add(signedTotals, 96),
                //right-shift by 160 to get just the 96 bits we want
                shr(
                    160,
                    //load data beginning 12 bytes before the end of the 'stakes' object (this is where totalEigenStake begins)
                    calldataload(
                        sub(pointer, 12)
                    )                                 
                )
            )
        }

        // transitory variables to be reused in loop
        // current signer information
        SignatureWithInfo memory sigWInfo;
        // previous signer's address, converted to a uint160. addresses are checked to be in strict numerical order (low => high), so this is initalized as zero
        uint160 previousSigner;

        // store all signers in memory, to be compressed  into 'compressedSignatoryRecord', along with the taskNumberToConfirm and the signed totals
        address[] memory signers = new address[](numberOfSigners);

        // loop for each signature ends once all signatures have been processed
        uint256 i;

        // pointer for calldata
        uint32 signatoryCalldataByteLocation;

        // loop through signatures
        for (; i < numberOfSigners; ) {

            assembly {
                //load r
                mstore(sigWInfo, calldataload(pointer))
                //load vs
                mstore(add(sigWInfo, 32), calldataload(add(pointer, 32)))
                //gets specified location of signatory in stakes object
                signatoryCalldataByteLocation := 
                    add(
                        //get position in calldata for start of stakes object
                        START_OF_STAKES_BYTE_LOCATION,
                        mul(
                            //gets specified index of signatory in stakes object
                            shr(
                                224,
                                    //64 accounts for length of signature components
                                    calldataload(add(pointer, 64)
                                )
                            ),
                            //20 + 12*2 for (address, uint96, uint96)
                            44
                        )
                    )
            }

            // actually check the signature
            sigWInfo.signatory = ECDSA.recover(signedHash, sigWInfo.r, sigWInfo.vs);

            // increase calldataPointer to account for length of signature components + 4 bytes for length of uint32 used to specify index in stakes object
            unchecked {
                pointer += 68;                    
            }

            // verify monotonic increase of address value
            require(
                uint160(sigWInfo.signatory) > previousSigner,
                "bad sig ordering"
            );

            // store signer info in memory variables
            previousSigner = uint160(sigWInfo.signatory);
            signers[i] = sigWInfo.signatory;

            assembly {
                //this block ensures that the recovered signatory address matches the address stored at the specified index in the stakes object
                //wrap inner part in revert statement (eq will return 0 if *not* equal, in which case, we revert)
                if iszero(
                    //check signatory address against address stored at specified index in stakes object
                    eq(
                        //gets signatory address
                        and(
                            //signatory location in sigWInfo
                            mload(add(sigWInfo, 64)),
                            //20 byte mask
                            TWENTY_BYTE_MASK
                        ),
                        //pulls address from stakes object
                        shr(
                            96,
                            calldataload(signatoryCalldataByteLocation)
                        )
                    )
                ) {
                    revert(0, 0)
                }

                //update ethStakeSigned (total)
                mstore(
                    signedTotals,
                    add(
                        mload(signedTotals),
                        //stake amount is 12 bytes, so right-shift by 160 bits (20 bytes)
                        shr(
                            160,
                            calldataload(
                                //adding 20 (bytes for signatory address) to previous index gets us index of ethStakeAmount for signatory
                                add(
                                    signatoryCalldataByteLocation,
                                    20
                                )
                            )
                        )
                    )
                )
                //update eigenStakeSigned (total)
                mstore(
                    add(signedTotals, 32),
                    add(
                        mload(add(signedTotals, 32)),
                        //stake amount is 16 bytes, so right-shift by 160 bits (20 bits)
                        shr(
                            160,
                            calldataload(
                                //adding 32 to previous index (20 for signatory, plus 12 for ethStake) gets us index of eigenStakeAmount for signatory
                                add(signatoryCalldataByteLocation,
                                    32
                                )
                            )
                        )
                    )
                )             
            }

            //increment counter at end of loop
            unchecked {
                ++i;
            }
        }


        // set compressedSignatoryRecord variable used for payment fraudproofs
        compressedSignatoryRecord = keccak256(
            abi.encodePacked(
                // taskHash,
                taskNumberToConfirm,
                signers,
                signedTotals.ethStakeSigned,
                signedTotals.eigenStakeSigned
            )
        );

        // return taskNumber, taskHash, eth and eigen that signed, and a hash of the signatories
        return (
            taskNumberToConfirm,
            taskHash,
            signedTotals,
            compressedSignatoryRecord
        );
    }
}