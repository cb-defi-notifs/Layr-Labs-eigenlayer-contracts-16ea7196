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
        uint8 stakerType;
        uint32 ethStakesIndexOfSignatory;
        uint32 eigenStakesIndexOfSignatory;
        address signatory;
    }

    struct StakesMetaData {
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

        uint256 pointer = 6 + 32 + 4;
        //subtract 88 because library takes offset into account
        //TODO: Optimize mstores
        smd.ethStakesIndex = data.toUint256(pointer);
        smd.eigenStakesIndex = data.toUint256(pointer + 32);
        smd.ethStakesLength = data.toUint256(pointer + 64);
        smd.eigenStakesLength = data.toUint256(pointer + 96);

        //just read 4* 32 bytes
        pointer += 128;
        //initialize at value that will be used in next calldataload (just after all the already loaded data)
        //load and verify integrity of eigen and eth stake hashes
        smd.ethStakes = data.slice(pointer, smd.ethStakesLength);
        pointer += smd.ethStakesLength;
        require(
            keccak256(smd.ethStakes) ==
                dlRegVW.getEthStakesHashUpdateAndCheckIndex(
                    smd.ethStakesIndex,
                    dumpNumberToConfirm
                ),
            "Eth stakes are incorrect"
        );
        smd.eigenStakes = data.slice(pointer, smd.eigenStakesLength);
        pointer += smd.eigenStakesLength;
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
        while (i < numberOfSigners) {
            //use library here because idk how to store struc in assembly
            //68 bytes is the encoding of bytes calldata offset, it's already counted in the lib
            sigWInfo.r = data.toBytes32(pointer);
            sigWInfo.vs = data.toBytes32(pointer + 32);
            sigWInfo.stakerType = data.toUint8(pointer + 64);
            sigWInfo.signatory = ECDSA.recover(
                signedHash,
                sigWInfo.r,
                sigWInfo.vs
            );
            //increase calldataPointer to account for length of signature and staker markers
            pointer += 64;

            //verify monotonic increase of address value
            require(
                uint160(sigWInfo.signatory) > previousSigner,
                "bad sig ordering"
            );
            //store signer info in memory variables
            previousSigner = uint160(sigWInfo.signatory);
            signers[i] = sigWInfo.signatory;

            if (sigWInfo.stakerType % 2 == 0) {
                //then they are an eth staker
                sigWInfo.ethStakesIndexOfSignatory = data.toUint32(pointer);
                require(
                    smd.ethStakes.toAddress(
                        sigWInfo.ethStakesIndexOfSignatory * 36
                    ) == sigWInfo.signatory,
                    "Eth stakes signatory index incorrect"
                );
                pointer += 4;
                //increment totals
                signedTotals.ethStakeSigned += smd.ethStakes.toUint128(
                    sigWInfo.ethStakesIndexOfSignatory * 36 + 20
                );
            }
            if (sigWInfo.stakerType % 3 == 0) {
                //then they are an eigen staker
                sigWInfo.eigenStakesIndexOfSignatory = data.toUint32(pointer);
                require(
                    smd.eigenStakes.toAddress(
                        sigWInfo.eigenStakesIndexOfSignatory * 36
                    ) == sigWInfo.signatory,
                    "Eth stakes signatory index incorrect"
                );
                pointer += 4;
                //increment totals
                signedTotals.eigenStakeSigned += smd.eigenStakes.toUint128(
                    sigWInfo.eigenStakesIndexOfSignatory * 36 + 20
                );
            }

            //increment counter at end of loop
            unchecked {
                ++i;
            }
        }

        //set compressedSignatoryRecord variable
        compressedSignatoryRecord = keccak256(
            abi.encodePacked(
                headerHash,
                dumpNumberToConfirm,
                abi.encodePacked(signers)
            )
        );
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
}
