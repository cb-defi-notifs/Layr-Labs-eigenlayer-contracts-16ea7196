// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrVoteWeigher.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./storage/DataLayrServiceManagerStorage.sol";
import "../../libraries/BytesLib.sol";
import "../../utils/SignatureCompaction.sol";
// import "ds-test/test.sol";

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
//TODO: determine if we need this
        //fills the 32-byte memory slot (prevents overwriting anything important)
        uint96 garbageData;
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
    packed tuple of address, uint96, uint96
        the uint96's are the ETH and EIGEN stake of the signatory (address)
    sigWInfo layout:
    bytes32 r
    bytes32 vs
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

            assembly {
                //load r
                mstore(sigWInfo, calldataload(add(pointer, 100)))
                //load vs
                mstore(add(sigWInfo, 32), calldataload(add(pointer, 132)))
                // signatoryCalldataByteLocation := 
                //                 add(
                //                     //get position in calldata for start of stakes object
                //                     mload(smd),
                //                             sigWInfo.stakesByteLocation
                //                 )
                signatoryCalldataByteLocation := 
                                add(
                                    //get position in calldata for start of stakes object
                                    mload(smd),
                                        mul(
                                            //gets specified location of signatory in stakes object
                                            shr(
                                                224,
                                                    calldataload(
                                                        //100 + 32 + 32
                                                        add(pointer, 164)
                                                )
                                            ),
                                            //20 + 12*2 for (address, uint96, uint96)
                                            44
                                        )
                                )
            }

            sigWInfo.signatory = SignatureCompaction.ecrecoverPacked(signedHash, sigWInfo.r, sigWInfo.vs);

            //increase calldataPointer to account for length of signature components
            unchecked {
                pointer += 64;                    
            }

            // emit log_named_uint("previousSigner", previousSigner);
            // emit log_named_address("sigWInfo.signatory", sigWInfo.signatory);
            // emit log_named_uint("uint160(sigWInfo.signatory)", uint160(sigWInfo.signatory));
            //verify monotonic increase of address value
            require(
                uint160(sigWInfo.signatory) > previousSigner,
                "bad sig ordering"
            );
            //store signer info in memory variables
            previousSigner = uint160(sigWInfo.signatory);
            signers[i] = sigWInfo.signatory;

            //BEGIN ADDED FOR TESTING
            // address addrFromSigWInfo;
            // address addrFromStakes;
            // uint256 ethStakeAmount;
            // assembly {
            //     addrFromSigWInfo := 
            //             //gets signatory address
            //             and(
            //                 //signatory location in sigWInfo
            //                 mload(add(sigWInfo, 64)),
            //                 //20 byte mask
            //                 0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
            //             )
            //     addrFromStakes :=
            //             //pulls address from stakes object
            //             shr(
            //                 96,
            //                 calldataload(signatoryCalldataByteLocation)
            //             )
            //     ethStakeAmount :=
            //                 shr(
            //                     160,
            //                     calldataload(
            //                         //adding 20 to previous (signatory) index gets us index of ethStakeAmount for signatory
            //                         add(
            //                             signatoryCalldataByteLocation,
            //                             20
            //                         )
            //                     )
            //                 )
            // }
            // emit log_named_bytes("full calldata", msg.data);
            // emit log_named_uint("signatoryCalldataByteLocation", signatoryCalldataByteLocation);
            // emit log_named_address("addrFromSigWInfo", addrFromSigWInfo);
            // emit log_named_address("sigWInfo.signatory", sigWInfo.signatory);
            // emit log_named_address("addrFromStakes", addrFromStakes);
            // emit log_named_uint("ethStakeAmount", ethStakeAmount);
            //END ADDED FOR TESTING


            //this block ensures that the recovered signatory address matches the address stored at the specified index in the stakes object
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

//            if (stakerType & 0x00000001 == 0x00000001) {
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
            // }

            // emit log_named_uint("stakerType2", stakerType);
            
            // if (stakerType & 0x00000003 == 0x00000003) {
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
            // }

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
}