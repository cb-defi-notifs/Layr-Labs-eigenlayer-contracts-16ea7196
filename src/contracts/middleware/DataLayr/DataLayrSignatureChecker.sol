// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./DataLayrServiceManagerStorage.sol";
import "../../libraries/BytesLib.sol";
import "../../libraries/SignatureCompaction.sol";
// import "ds-test/test.sol";

abstract contract DataLayrSignatureChecker is
    DataLayrServiceManagerStorage
    // , DSTest
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
        //fills the 32-byte memory slot (prevents overwriting anything important in dirty-write of 'signatory')
        uint96 garbageData;
    }

    struct StakesMetaData {
        //index of stakeHashUpdate
        uint256 stakesIndex;
        //length of stakes object
        uint256 stakesLength;
        //stakes object
        bytes stakes;
    }

    //NOTE: this assumes length 64 signatures
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
        assembly {
            //get the 48 bits immediately after the function signature and length encoding of bytes calldata type
            dumpNumberToConfirm := shr(208, calldataload(68))
            //get the 32 bytes immediately after the above
            headerHash := calldataload(74)
            //get the next 32 bits
            numberOfSigners := shr(224, calldataload(106))
            //store the next 32 bytes in the start of the 'smd' object (i.e. smd.stakesIndex)
            mstore(smd, calldataload(110))
            //store the next 32 bytes after the start of the 'smd' object (i.e. smd.stakesLength)
            mstore(add(smd, 32), calldataload(142))
        }

        bytes32 signedHash = ECDSA.toEthSignedMessageHash(headerHash);

        // TODO: Optimize mstores further?
        // emit log_named_bytes("calldata", msg.data);
        // emit log_named_uint("smd.stakesIndex", smd.stakesIndex);

        // total bytes read so far is now (6 + 32 + 4 + 64) = 106
        // load stakes into memory and verify integrity of stake hash
        smd.stakes = data.slice(106, smd.stakesLength);
        require(
            keccak256(smd.stakes) ==
                IDataLayrVoteWeigher(address(repository.voteWeigher())).getStakesHashUpdateAndCheckIndex(
                    smd.stakesIndex,
                    dumpNumberToConfirm
                ),
            "ETH and/or EIGEN stakes are incorrect"
        );

        // initialize at value that will be used in next calldataload (just after all the already loaded data)
        // we add 68 to the amount of data we have read here (174 = 106 + 68), since 4 bytes (for function sig) + (32 * 2) bytes is used at start of calldata
        uint256 pointer = 174 + smd.stakesLength;

        assembly {
            //fetch the totalEthStake value and store it in memory
            mstore(
                //signedTotals.totalEthStake location
                add(signedTotals, 64),
                //right-shift by 160 to get just the 96 bits we want
                shr(
                    160,
                    //load data beginning 24 bytes before the end of the 'stakes' object (this is where totalEthStake begins)
                    calldataload(sub(pointer, 24))                 
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
                    calldataload(sub(pointer, 12))                 
                )
            )
        }

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
                mstore(sigWInfo, calldataload(pointer))
                //load vs
                mstore(add(sigWInfo, 32), calldataload(add(pointer, 32)))
                // signatoryCalldataByteLocation := 
                //                 add(
                //                     //get position in calldata for start of stakes object
                //                     mload(smd),
                //                             sigWInfo.stakesByteLocation
                //                 )
                signatoryCalldataByteLocation := 
                                add(
                                    //get position in calldata for start of stakes object
                                    174,
                                        mul(
                                            //gets specified location of signatory in stakes object
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

            sigWInfo.signatory = SignatureCompaction.ecrecoverPacked(signedHash, sigWInfo.r, sigWInfo.vs);

            //increase calldataPointer to account for length of signature components + 4 bytes for length of uint32 used to specify index in stakes object
            unchecked {
                pointer += 68;                    
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
            //emit log_uint(gasleft());

        //set compressedSignatoryRecord variable
        compressedSignatoryRecord = keccak256(
            abi.encodePacked(
                headerHash,
                dumpNumberToConfirm,
                abi.encodePacked(signers)
            )
        );

        // emit log_named_uint("signedTotals.ethStakeSigned", signedTotals.ethStakeSigned);
        // emit log_named_uint("signedTotals.eigenStakeSigned", signedTotals.eigenStakeSigned);
        // emit log_named_uint("signedTotals.totalEthStake", signedTotals.totalEthStake);
        // emit log_named_uint("signedTotals.totalEigenStake", signedTotals.totalEigenStake);
        // emit log_named_uint("smd.stakesLength", smd.stakesLength);

        //return dumpNumber, headerHash, eth and eigen that signed, and a hash of the signatories
        return (
            dumpNumberToConfirm,
            headerHash,
            signedTotals,
            compressedSignatoryRecord
        );
    }
}