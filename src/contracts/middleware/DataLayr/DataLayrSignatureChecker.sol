// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrVoteWeigher.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./storage/DataLayrServiceManagerStorage.sol";
import "../../libraries/BytesLib.sol";

abstract contract DataLayrSignatureChecker is DataLayrServiceManagerStorage {
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
    bytes32 ferkleRoot,
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
            bytes32 ferkleRoot,
            SignatoryTotals memory signedTotals,
            bytes32 compressedSignatoryRecord
        )
    {
        //dumpNumber corresponding to the ferkleRoot
        //number of different signature bins that signatures are being posted from
        uint32 numberOfSigners;
        StakesMetaData memory smd;
        //signed data
        //bytes32 ferkleRoot;
        assembly {
            //get the 48 bits immediately after the function signature and length encoding of bytes calldata type
            dumpNumberToConfirm := shr(208, calldataload(68))
            //get the 32 bytes immediately after the above
            ferkleRoot := calldataload(76)
            //get the next 32 bits
            numberOfSigners := shr(224, calldataload(108))
        }
        //subtract 68 because library takes offset into account
        //TODO: Optimize mstores
        smd.ethStakesIndex = data.toUint256(44);
        smd.eigenStakesIndex = data.toUint256(76);
        smd.ethStakesLength = data.toUint256(108);
        smd.eigenStakesLength = data.toUint256(140);
        //initialize at value that will be used in next calldataload (just after all the already loaded data)
        uint256 calldataPointer = 240;
        //load and verify integrity of eigen and eth stake hashes
        smd.ethStakes = msg.data.slice(
            calldataPointer,
            smd.ethStakesLength
        );
        calldataPointer += smd.ethStakesLength;
        require(
            keccak256(smd.ethStakes) ==
                dlRegVW.getEthStakesHashUpdateAndCheckIndex(
                    smd.ethStakesIndex,
                    dumpNumberToConfirm
                ),
            "Eth stakes are incorrect"
        );
        smd.eigenStakes = msg.data.slice(
            calldataPointer,
            smd.eigenStakesLength
        );
        calldataPointer += smd.eigenStakesLength;
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
            sigWInfo.r = data.toBytes32(calldataPointer - 68);
            sigWInfo.vs = data.toBytes32(calldataPointer - 36);
            sigWInfo.stakerType = data.toUint8(calldataPointer - 4);
            sigWInfo.signatory = ECDSA.recover(ferkleRoot, sigWInfo.r, sigWInfo.vs);
            //increase calldataPointer to account for length of signature and staker markers
            calldataPointer += 65;

            //verify monotonic increase of address value
            require(uint160(sigWInfo.signatory) > previousSigner, "bad sig ordering");
            //store signer info in memory variables
            previousSigner = uint160(sigWInfo.signatory);
            signers[i] = sigWInfo.signatory;

            if(sigWInfo.stakerType % 2 == 0) {
                //then they are an eth staker
                sigWInfo.ethStakesIndexOfSignatory = data.toUint32(calldataPointer);
                require(smd.ethStakes.toAddress(sigWInfo.ethStakesIndexOfSignatory * 36) == sigWInfo.signatory, "Eth stakes signatory index incorrect");
                calldataPointer += 4;
                //increment totals
                signedTotals.ethStakeSigned += smd.ethStakes.toUint128(sigWInfo.ethStakesIndexOfSignatory * 36 + 20);
            }
            if(sigWInfo.stakerType % 3 == 0) {
                //then they are an eigen staker
                sigWInfo.eigenStakesIndexOfSignatory = data.toUint32(calldataPointer);
                require(smd.eigenStakes.toAddress(sigWInfo.eigenStakesIndexOfSignatory * 36) == sigWInfo.signatory, "Eth stakes signatory index incorrect");
                calldataPointer += 4;
                //increment totals
                signedTotals.eigenStakeSigned += smd.eigenStakes.toUint128(sigWInfo.eigenStakesIndexOfSignatory * 36 + 20);
            }

            //increment counter at end of loop
            unchecked {
                ++i;
            }
        }

        //set compressedSignatoryRecord variable
        compressedSignatoryRecord = keccak256(
            abi.encodePacked(
                ferkleRoot,
                dumpNumberToConfirm,
                abi.encodePacked(signers)
            )
        );
        signedTotals.totalEthStake = smd.ethStakes.toUint256(smd.ethStakesLength - 33);
        signedTotals.totalEigenStake = smd.eigenStakes.toUint256(smd.eigenStakesLength - 33);
        //return dumpNumber, ferkle root, eth and eigen that signed and a hash of the signatories
        return (
            dumpNumberToConfirm,
            ferkleRoot,
            signedTotals,
            compressedSignatoryRecord
        );
    }
}
