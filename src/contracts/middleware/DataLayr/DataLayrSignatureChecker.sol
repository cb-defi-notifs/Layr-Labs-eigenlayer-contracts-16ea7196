// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrVoteWeigher.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./storage/DataLayrServiceManagerStorage.sol";
import "../../libraries/BytesLib.sol";
import "ds-test/test.sol";

abstract contract DataLayrSignatureChecker is
    DataLayrServiceManagerStorage,
    DSTest
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
        uint256 ethStakesPointer;
        uint256 eigenStakesPointer;
        //index of ethStakeHashUpdate
        uint256 ethStakesIndex;
        //index of eigenStakeHashUpdate
        uint256 eigenStakesIndex;
        //length of eth stakes
        uint256 ethStakesLength;
        //length of eigen stakes
        uint256 eigenStakesLength;
        bytes ethStakes;
        bytes eigenStakes;
    }

    //NOTE: this assumes length 64 signatures
    //TODO: sanity check on calldata length?
    //TODO: do math instead of updating calldataPointer variable?
    /*
    FULL CALLDATA FORMAT:
    uint48 dumpNumber,
    bytes32 headerHash,
    uint32 numberOfSigners,
    uint256 ethStakesIndex, uint256 eigenStakesIndex,
    uint256 ethStakesLength, uint256 eigenStakesLength,
    bytes ethStakes, bytes eigenStakes,
    bytes sigWInfos (number of sigWInfos provided here is equal to numberOfSigners)

    ethStakes layout:
    packed uint128, one for each signatory that is an ETH signatory (signaled by setting stakerType % 2 == 0)

    eigenStakes layout:
    packed uint128, one for each signatory that is an EIGEN signatory (signaled by setting stakerType % 3 == 0)

    sigWInfo layout:
    bytes32 r
    bytes32 vs
    bytes1 stakerType
    if (sigWInfo.stakerType % 2 == 0) {
        uint32 ethStakesIndex of signatory
    }
    if (sigWInfo.stakerType % 3 == 0) {
        uint32 eigenStakesIndex of signatory
    }

    Explanation for stakerType:
                                stakerType = 0 means both ETH & EIGEN signatory (equivalent to 6)
                                stakerType = 2 means *only* ETH signatory (equivalent to 4 or 8)
                                stakerType = 3 means *only* EIGEN signatory
                                stakerType = 1 means *neither* type of signatory (useless, equivalent to 5 or 7)

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

        //emit log_named_uint("dumpNumberToConfirm", dumpNumberToConfirm);
        //emit log_named_uint("data.length", data.length);

        //add together length of already read data
        uint256 pointer = 6 + 32 + 4;
        //subtract 88 because library takes offset into account
        //TODO: Optimize mstores
        smd.ethStakesIndex = data.toUint256(pointer);
        smd.eigenStakesIndex = data.toUint256(pointer + 32);
        smd.ethStakesLength = data.toUint256(pointer + 64);
        smd.eigenStakesLength = data.toUint256(pointer + 96);

        //emit log_named_uint("smd.ethStakesIndex", smd.ethStakesIndex);
        //emit log_named_uint("smd.eigenStakesIndex", smd.eigenStakesIndex);

        //just read 4* 32 bytes
        unchecked {
            pointer += 128;            
        }
        //initialize at value that will be used in next calldataload (just after all the already loaded data)
        //load and verify integrity of eigen and eth stake hashes
        smd.ethStakes = data.slice(pointer, smd.ethStakesLength);
        smd.ethStakesPointer = pointer + 100;
        unchecked {
            pointer += smd.ethStakesLength;            
        }
        require(
            keccak256(smd.ethStakes) ==
                dlRegVW.getEthStakesHashUpdateAndCheckIndex(
                    smd.ethStakesIndex,
                    dumpNumberToConfirm
                ),
            "Eth stakes are incorrect"
        );
        smd.eigenStakes = data.slice(pointer, smd.eigenStakesLength);
        smd.eigenStakesPointer = pointer + 100;
        unchecked {
            pointer += smd.eigenStakesLength;            
        }
        require(
            keccak256(smd.eigenStakes) ==
                dlRegVW.getEigenStakesHashUpdateAndCheckIndex(
                    smd.eigenStakesIndex,
                    dumpNumberToConfirm
                ),
            "Eigen stakes are incorrect"
        );

        //transitory variables to be reused in loop
        //current signer information
        SignatureWithInfo memory sigWInfo;
        //previous signer's address, converted to a uint160. addresses are checked to be in strict numerical order (low => high), so this is initalized as zero
        uint160 previousSigner;

        //store all signers in memory, to be compressed  into 'compressedSignatoryRecord', along with the ferkle root and the dumpNumberToConfirm
        address[] memory signers = new address[](numberOfSigners);

        //loop for each signatures ends once all signatures have been processed
        uint256 i;
            //emit log_uint(gasleft());

        while (i < numberOfSigners) {
            // emit log_named_uint("i (numberOfSigners)", i);

            //use library here because idk how to store struc in assembly
            //68 bytes is the encoding of bytes calldata offset, it's already counted in the lib
            assembly {
                //load r
                mstore(sigWInfo, calldataload(add(pointer, 100)))
                //load vs
                mstore(add(sigWInfo, 32), calldataload(add(pointer, 132)))
                //load registrantType (single byte)
                mstore(
                    //84 = 64 + 20 (64 bytes for signature, 20 bytes for signatory)
                    add(sigWInfo, 84),
                    and(
                        calldataload(add(pointer, 164)),
                        //single byte mask (throw out the last 31 bytes)
                        0xFF00000000000000000000000000000000000000000000000000000000000000
                    )
                )
            }
            sigWInfo.signatory = ecrecover(
                signedHash,
                //recover v (parity)
                27 + uint8(uint256(sigWInfo.vs >> 255)),
                sigWInfo.r,
                //recover s
                bytes32(uint(sigWInfo.vs) & (~uint(0) >> 1))
            );
            // ECDSA.recover(
            //     signedHash,
            //     sigWInfo.r,
            //     sigWInfo.vs
            // );
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
            if (sigWInfo.stakerType % 2 == 0) {
                //BEGIN ADDED
                address addrFromEthStakes;
                uint256 numPulledInAssembly;
                assembly {
                    addrFromEthStakes := 
                            shr(
                                96,
                                calldataload(
                                    add(
                                        //get position in calldata for start of ethStakes object
                                        mload(smd),
                                        //get byte location of signatory in ethStakes object
                                        mul(
                                            //gets ethStakesIndex (of signatory)
                                            shr(
                                                224,
                                                calldataload(
                                                    add(100, pointer)
                                                )
                                            ),
                                            //length of a single 'stake' in ethStakes object
                                            36
                                        )
                                    )
                                )
                            )
                    numPulledInAssembly :=
                                            shr(
                                                224,
                                                calldataload(
                                                    add(100, pointer)
                                                )
                                            )
                }
                // emit log_named_address("addrFromEthStakes", addrFromEthStakes);
                // emit log_named_uint("numPulledInAssembly", numPulledInAssembly);
                //END ADDED
                assembly {
                    // store 36 * index at random key
                    if iszero(
                        //check signatory address against address stored at specified index in ethStakes
                        eq(
                            //gets signatory address
                            and(
                                //signatory location in sigWInfo
                                mload(add(sigWInfo, 64)),
                                //20 byte mask
                                0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
                            ),
                            //pulls address from ethStakes
                            shr(
                                96,
                                calldataload(
                                    add(
                                        //get pointer in calldata to start of ethStakes object
                                        mload(smd),
                                        //get byte location of signatory in ethStakes object
                                        mul(
                                            //gets ethStakesIndex (of signatory)
                                            shr(
                                                224,
                                                calldataload(
                                                    add(100, pointer)
                                                )
                                            ),
                                            //length of a single 'stake' in ethStakes object
                                            36
                                        )
                                    )
                                )
                            )
                        )
                    ) {
                        revert(0, 0)
                    }
                //BEGIN ADDED
                }
                // emit log_named_uint("what", 0);
                assembly {
                //END ADDED
                    //update ethStakeSigned (total)
                    mstore(
                        signedTotals,
                        add(
                            mload(signedTotals),
                            //stake amount is 16 bytes, so right-shift by 128 bits
                            shr(
                                128,
                                calldataload(
                                    add(
                                        mload(smd),
                                        //adding 20 to previous (signatory) index gets us index of stakeAmount for signatory
                                        add(
                                            //same index as before (signatory)
                                            mul(
                                                shr(
                                                    224,
                                                    calldataload(
                                                        add(100, pointer)
                                                    )
                                                ),
                                                36
                                            ),
                                            20
                                        )
                                    )
                                )
                            )
                        )
                    )
                }
                //add 4 bytes for length of uint32 used to specify index in ethStakes object
                unchecked {
                    pointer += 4;                    
                }
            }

            // emit log_named_uint("sigWInfo.stakerType2", sigWInfo.stakerType);

            if (sigWInfo.stakerType % 3 == 0) {
                // store 36 * index at random key
                assembly {
                    if iszero(
                        eq(
                            and(
                                mload(add(sigWInfo, 64)),
                                0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
                            ),
                            shr(
                                96,
                                calldataload(
                                    add(
                                        mload(add(smd, 32)),
                                        mul(
                                            shr(
                                                224,
                                                calldataload(
                                                    add(100, pointer)
                                                )
                                            ),
                                            36
                                        )
                                    )
                                )
                            )
                        )
                    ) {
                        revert(0, 0)
                    }
                    mstore(
                        add(signedTotals, 32),
                        add(
                            mload(add(signedTotals, 32)),
                            shr(
                                128,
                                calldataload(
                                    add(
                                        mload(add(smd, 32)),
                                        add(
                                            mul(
                                                shr(
                                                    224,
                                                    calldataload(
                                                        add(100, pointer)
                                                    )
                                                ),
                                                36
                                            ),
                                            20
                                        )
                                    )
                                )
                            )
                        )
                    )
                }
                //add 4 bytes for length of uint32 used to specify index in eigenStakes object
                unchecked {
                    pointer += 4;                    
                }
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

        //emit log_named_uint("signedTotals.totalEthStake", signedTotals.totalEthStake);
        //emit log_named_uint("smd.ethStakesLength", smd.ethStakesLength);

        signedTotals.totalEthStake = smd.ethStakes.toUint256(
            smd.ethStakesLength - 33
        );
        signedTotals.totalEigenStake = smd.eigenStakes.toUint256(
            smd.eigenStakesLength - 33
        );

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
