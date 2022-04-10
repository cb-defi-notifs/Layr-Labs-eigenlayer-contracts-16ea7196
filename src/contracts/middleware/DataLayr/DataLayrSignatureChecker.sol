// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrVoteWeigher.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./storage/DataLayrServiceManagerStorage.sol";
import "../../libraries/BytesLib.sol";
import "../../utils/SignatureCompaction.sol";

abstract contract DataLayrSignatureChecker is
    DataLayrServiceManagerStorage
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
        uint8 stakerType;
    }

    struct StakesMetaData {
        uint256 stakesPointer;
        //index of stakeHashUpdate
        uint256 stakesIndex;
        //length of stakes object
        uint256 stakesLength;
        //stakes object
        bytes stakes;
    }

    //NOTE: this assumes length 64 signatures
    //TODO: sanity check on calldata length?
    //TODO: do math instead of updating calldataPointer variable?
    /*
    FULL CALLDATA FORMAT:
    uint48 dumpNumber,
    bytes32 headerHash,
    uint32 numberOfSigners,
    uint256 stakesIndex,
    uint256 stakesLength,
    bytes stakes,
    bytes sigWInfos (number of sigWInfos provided here is equal to numberOfSigners)

    stakes layout:
    packed tuple of stakerType, address, uint96 (and possible second uint96)
        the uint96's are the ETH and/or EIGEN stake of the signatory (address), signalled by setting first 2 bit of stakerType
        signatory is an ETH signatory if first bit in stakerType set to '1' (i.e. stakerType & 0x00000001 == 0x00000001)
        signatory is an EIGEN signatory if second bit in stakerType set to '1' (i.e. stakerType & 0x00000003 == 0x00000003)
    eigenStakes layout:
    packed uint128, one for each signatory that is an EIGEN signatory (signaled by setting stakerType & 0x00000003 == 0x00000003)

    sigWInfo layout:
    bytes32 r
    bytes32 vs
    bytes1 stakerType
    uint32 bytes location in 'stakes' of signatory

    */
    function checkSignatures(bytes calldata data)
        public
        returns (
            uint48 dumpNumberToConfirm,
            bytes32 headerHash,
            SignatoryTotals memory signedTotals,
            bytes32 compressedSignatoryRecord
        )
    {
        //dumpNumber corresponding to the headerHash
        //number of different signature bins that signatures are being posted from
        uint32 numberOfSigners;
        StakesMetaData memory smd;
        //signed data
        //bytes32 headerHash;
        assembly {
            //get the 48 bits immediately after the function signature and length encoding of bytes calldata type
            dumpNumberToConfirm := shr(208, calldataload(100))
            //get the 32 bytes immediately after the above
            headerHash := calldataload(106)
            //get the next 32 bits
            numberOfSigners := shr(224, calldataload(138))
        }

        bytes32 signedHash = ECDSA.toEthSignedMessageHash(headerHash);

        //add together length of already read data
        uint256 pointer = 6 + 32 + 4;
        //subtract 88 because library takes offset into account
        //TODO: Optimize mstores
        smd.stakesIndex = data.toUint256(pointer);
        smd.stakesLength = data.toUint256(pointer + 32);

        //emit log_named_uint("smd.stakesIndex", smd.stakesIndex);
        //emit log_named_uint("smd.eigenStakesIndex", smd.eigenStakesIndex);

        //just read 2 * 32 additional bytes
        unchecked {
            pointer += 64;            
        }
        //initialize at value that will be used in next calldataload (just after all the already loaded data)
        //load and verify integrity of stake hash
        smd.stakes = data.slice(pointer, smd.stakesLength);
        smd.stakesPointer = pointer + 100;
        unchecked {
            pointer += smd.stakesLength;            
        }
        require(
            keccak256(smd.stakes) ==
                dlRegVW.getStakesHashUpdateAndCheckIndex(
                    smd.stakesIndex,
                    dumpNumberToConfirm
                ),
            "ETH and/or EIGEN stakes are incorrect"
        );

        //transitory variables to be reused in loop
        //current signer information
        SignatureWithInfo memory sigWInfo;
        //previous signer's address, converted to a uint160. addresses are checked to be in strict numerical order (low => high), so this is initalized as zero
        uint160 previousSigner;

        //store all signers in memory, to be compressed  into 'compressedSignatoryRecord', along with the ferkle root and the dumpNumberToConfirm
        address[] memory signers = new address[](numberOfSigners);

        uint32 signatoryCalldataByteLocation;

        //loop for each signatures ends once all signatures have been processed
        uint256 i;
            //emit log_uint(gasleft());

        while (i < numberOfSigners) {
            // emit log_named_uint("i (numberOfSigners)", i);
            // emit log_named_uint("pointer at loop start", pointer);

            //use library here because idk how to store struc in assembly
            //68 bytes is the encoding of bytes calldata offset, it's already counted in the lib
            // uint8 st;
            assembly {
                //load r
                mstore(sigWInfo, calldataload(add(pointer, 100)))
                //load vs
                mstore(add(sigWInfo, 32), calldataload(add(pointer, 132)))
                //load registrantType (single byte)
                // st := shr(248, calldataload(add(pointer, 164))) 
//TODO: FIX THIS! (why is it broken?)
                // mstore(
                //     //84 = 64 + 20 (64 bytes for signature, 20 bytes for signatory)
                //     add(sigWInfo, 84),
                //     shr(248, calldataload(add(pointer, 164)))
                //     // and(
                //     //     calldataload(add(pointer, 164)),
                //     //     //single byte mask (throw out the last 31 bytes)
                //     //     0xFF00000000000000000000000000000000000000000000000000000000000000
                //     // )
                // )
            }

            // sigWInfo.stakerType = st;
            // bytes32 vs;
            // // bytes32 vs;
            // assembly {
            //     vs := calldataload(add(pointer, 132))
            // }
            // emit log_named_bytes32("vs", vs);
            // emit log_named_bytes32("vs", calldataload(add(pointer, 132)));
            // emit log_named_uint("sigWInfo.stakerType0", sigWInfo.stakerType);

            // emit log_named_bytes("calldata", msg.data);

            assembly {
                signatoryCalldataByteLocation := 
                                add(
                                    //get position in calldata for start of stakes object
                                    mload(smd),
                                            //gets specified byte location of signatory in stakes object
                                            shr(
                                                224,
                                                    calldataload(
                                                        //100 + 32 + 32 + 1
                                                        add(pointer, 165)
                                                )
                                            )
                                )
            }
            // emit log_named_uint("signatoryCalldataByteLocation", signatoryCalldataByteLocation);

            //BEGIN ADDED FOR TESTING
            // emit log_named_uint("pointer plus 164", (pointer + 164));
            // bytes32 testing;
            // assembly {
            //     testing := calldataload(add(pointer, 164))
            // }
            // emit log_named_bytes32("testing", testing);
            // assembly {
            //     testing :=                     
            //         and(
            //             calldataload(add(pointer, 164)),
            //             //single byte mask (throw out the last 31 bytes)
            //             0xFF00000000000000000000000000000000000000000000000000000000000000
            //         )
            // }
            // emit log_named_bytes32("testing2", testing);

            // uint8 testing_uint8;
            // assembly {
            //     testing_uint8 := calldataload(add(pointer, 164))
            // }
            // emit log_named_uint("testing_uint8", testing_uint8);
            // assembly {
            //     testing_uint8 :=                     and(
            //             calldataload(add(pointer, 164)),
            //             //single byte mask (throw out the last 31 bytes)
            //             0xFF00000000000000000000000000000000000000000000000000000000000000
            //         )
            // }
            // emit log_named_uint("testing_uint8_2", testing_uint8);
            sigWInfo.stakerType = 3;
            //END ADDED FOR TESTING


//TODO: try this once things are working
            //sigWInfo.signatory = SignatureCompaction.ecrecoverPacked(signedHash, sigWInfo.r, sigWInfo.vs);

            sigWInfo.signatory = ecrecover(
                signedHash,
                //recover v (parity)
                27 + uint8(uint256(sigWInfo.vs >> 255)),
                sigWInfo.r,
                //recover s
                bytes32(uint(sigWInfo.vs) & (~uint(0) >> 1))
            );
            //increase calldataPointer to account for length of signature and staker markers
            unchecked {
                pointer += 65;                    
            }

            //verify monotonic increase of address value
            require(
                uint160(sigWInfo.signatory) > previousSigner,
                "bad sig ordering"
            );
            //store signer info in memory variables
            previousSigner = uint160(sigWInfo.signatory);
            signers[i] = sigWInfo.signatory;
            // emit log_named_address("sigWInfo.signatory", sigWInfo.signatory);
            // emit log_named_uint("sigWInfo.stakerType1", sigWInfo.stakerType);

            //BEGIN ADDED FOR TESTING
            address addrFromStakes;
            uint256 ethStakeAmount;
            assembly {
                addrFromStakes := 
                        shr(
                            96,
                            calldataload(
                                add(
                                    //get position in calldata for start of stakes object
                                    mload(smd),
                                    //gets specified byte location of signatory in stakes object
                                    shr(
                                        224,
                                        calldataload(
                                            add(100, pointer)
                                        )
                                    )
                                )
                            )
                        )
                ethStakeAmount :=
                            shr(
                                160,
                                calldataload(
                                    //adding 20 to previous (signatory) index gets us index of ethStakeAmount for signatory
                                    add(
                                        add(
                                            //get position in calldata for start of stakes object
                                            mload(smd),
                                            //gets specified byte location of signatory in stakes object
                                            shr(
                                                224,
                                                calldataload(
                                                    add(100, pointer)
                                                )
                                            )
                                        ),
                                        20
                                    )
                                )
                            )
            }
            // emit log_named_address("addrFromStakes", addrFromStakes);
            // emit log_named_uint("ethStakeAmount", ethStakeAmount);
            //END ADDED FOR TESTING

//TODO: check stored registrant type matches supplied type???

            assembly {
                //wrap inner part in revert statement (eq will return 0 if *not* equal, in which case, we revert)
                if iszero(
                    //check signatory address against address stored at specified index in stakes object
                    eq(
                        //gets signatory address
                        and(
                            //signatory location in sigWInfo
                            mload(add(sigWInfo, 64)),
                            //20 byte mask
                            0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
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
            }

            if (sigWInfo.stakerType & 0x00000001 == 0x00000001) {
                //BEGIN ADDED FOR TESTING
                // emit log_named_uint("break", 0);
                //END ADDED FOR TESTING
                assembly {
                    //update ethStakeSigned (total)
                    mstore(
                        signedTotals,
                        add(
                            mload(signedTotals),
                            //stake amount is 12 bytes, so right-shift by 160 bits (20 bytes)
                            shr(
                                160,
                                calldataload(
                                    //adding 20 to previous (signatory) index gets us index of ethStakeAmount for signatory
                                    add(
                                        signatoryCalldataByteLocation,
                                        20
                                    )
                                )
                            )
                        )
                    )
                }
                //add 12 bytes for length of uint96 used to specify size of ETH stake
                unchecked {
                    signatoryCalldataByteLocation += 12;                    
                }
            }

            // emit log_named_uint("sigWInfo.stakerType2", sigWInfo.stakerType);
            // emit log_named_uint("signedTotals.eigenStakeSigned", signedTotals.eigenStakeSigned);

            if (sigWInfo.stakerType & 0x00000003 == 0x00000003) {
                // emit log_named_uint("break", 1);
                assembly {
                    //update eigenStakeSigned (total)
                    mstore(
                        add(signedTotals, 32),
                        add(
                            mload(add(signedTotals, 32)),
                            //stake amount is 16 bytes, so right-shift by 160 bits (20 bits)
                            shr(
                                160,
                                calldataload(
                                    //adding 20 to previous (signatory, possibly plus 12 if eth validator) index gets us index of eigenStakeAmount for signatory
                                    add(signatoryCalldataByteLocation,
                                        20
                                    )
                                )
                            )
                        )
                    )
                }
            }

            //add 4 bytes for length of uint32 used to specify index in stakes object
            unchecked {
                pointer += 4;                    
            }
            //increment counter at end of loop
            unchecked {
                ++i;
            }
        }
            //emit log_uint(gasleft());

        //set compressedSignatoryRecord variable
        compressedSignatoryRecord = keccak256(
            abi.encodePacked(
                headerHash,
                dumpNumberToConfirm,
                abi.encodePacked(signers)
            )
        );

        signedTotals.totalEthStake = smd.stakes.toUint96(
            smd.stakesLength - 24
        );
        signedTotals.totalEigenStake = smd.stakes.toUint96(
            smd.stakesLength - 12
        );

        // emit log_named_uint("signedTotals.ethStakeSigned", signedTotals.ethStakeSigned);
        // emit log_named_uint("signedTotals.eigenStakeSigned", signedTotals.eigenStakeSigned);
        // emit log_named_uint("signedTotals.totalEthStake", signedTotals.totalEthStake);
        // emit log_named_uint("signedTotals.totalEigenStake", signedTotals.totalEigenStake);
        // emit log_named_uint("smd.stakesLength", smd.stakesLength);

        //return dumpNumber, ferkle root, eth and eigen that signed and a hash of the signatories
        return (
            dumpNumberToConfirm,
            headerHash,
            signedTotals,
            compressedSignatoryRecord
        );
    }

    // function getAddressIsh(
    //     SignatureWithInfo memory sigWInfo,
    //     StakesMetaData memory smd,
    //     SignatoryTotals memory signedTotals,
    //     uint256 pointer
    // ) internal {
    //     bytes32 sig;
    //     bytes32 osig;
    //     assembly {
    //         sig := mload(
    //             add(
    //                 mload(smd),
    //                 mul(shr(96, calldataload(add(100, pointer))), 36)
    //             )
    //         )

    //         // add(
    //         //     mload(signedTotals),
    //         //     shr(
    //         //         128,
    //         //         mload(
    //         //             add(
    //         //                 mload(smd),
    //         //                 add(
    //         //                     mul(
    //         //                         shr(224, calldataload(add(100, pointer))),
    //         //                         36
    //         //                     ),
    //         //                     20
    //         //                 )
    //         //             )
    //         //         )
    //         //     )
    //         // )
    //     }

    //     // emit log_bytes32(osig);
    // }
}
