// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrVoteWeigher.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./storage/DataLayrServiceManagerStorage.sol";

abstract contract DataLayrSignatureChecker is DataLayrServiceManagerStorage {
    struct SignatoryTotals {
        //total eth stake of the signatories
        uint32 totalEthSigners;
        //total eigen stake of the signatories
        uint32 totalEigenSigners;
    }

    //the DL vote weighter
    IDataLayrVoteWeigher public dlRegVW;

    //NOTE: this assumes length 64 signatures
    //TODO: sanity check on calldata length?
    //TODO: do math instead of updating calldataPointer variable?
    //TODO: better storage for signatoryIndices -- currently need 32 bits, which can be part of a struct
    //TODO: possibly checks on bins. e.g. 1+ sig per bin for some bins, > x for some bins, etc.
    //TODO: multiple indices for different things? e.g. one for ETH, one for EIGEN?
    /*
    FULL CALLDATA FORMAT:
    uint64 dumpNumber,
    bytes32 ferkleRoot,
    uint16 numberOfBins,
    [uint16 sigsInBin, uint32 binIndex [bytes32 r, bytes32 vs](sigsInBin)](number of bins)

    i.e.
    uint64, bytes32, uint16, followed by (number of bins) sets, of the format:
    uint16, uint32, bytes64 (signatures), with the number of signatures equal to the value of the uint16
    */
    function checkSignatures(bytes calldata)
        public
        returns (
            uint64 dumpNumberToConfirm,
            bytes32 ferkleRoot,
            SignatoryTotals memory signedTotals,
            bytes32 compressedSignatoryRecord
        )
    {
        //dumpNumber corresponding to the ferkleRoot
        //uint64 dumpNumberToConfirm;
        //number of different signature bins that signatures are being posted from
        uint16 numberOfBins;
        //signed data
        //bytes32 ferkleRoot;
        assembly {
            //get the 64 bits immediately after the function signature and length encoding of bytes calldata type
            dumpNumberToConfirm := shr(192, calldataload(68))
            //get the 32 bytes immediately after the above
            ferkleRoot := calldataload(76)
            //get the next 16 bits
            numberOfBins := shr(240, calldataload(108))
        }
        //initialize at value that will be used in next calldataload (just after all the already loaded data)
        uint32 calldataPointer = 110;
        //transitory variables to be reused in loops
        bytes32 r;
        bytes32 vs;
        address signatory;
        //number of signatures contained in the bin currently being processed
        uint16 sigsInCurrentBin;
        //index of current bin of signatures being processed. initially set to max value for a later check
        uint32 currentBinIndex = type(uint32).max;
        //temporary variable used to gaurantee that binIndices are strictly increasing. prevents usage of duplicate bins
        uint32 nextBinIndex;
        //temp variables initiated outside of loop -- these are updated inside of each inner loop
        uint32 operatorId;
        uint256 mask;
        //record of all signatories stored in the form: keccak256(abi.encodePacked(currentBinIndex, claimsMadeInBin, previousHash))
        //with first hash being that of the ferkleRoot + dumpNumber
        compressedSignatoryRecord = keccak256(
            abi.encodePacked(ferkleRoot, dumpNumberToConfirm)
        );
        //loop for each bin of signatures. ends once all bins have been processed
        while (numberOfBins > 0) {
            //update sigsInBin and binIndex for next bin
            assembly {
                //get the 16 bits at the current calldataPointer
                sigsInCurrentBin := shr(240, calldataload(calldataPointer))
                //get the 32 bits immediately after the 2 bytes for sigsInCurrentBin
                nextBinIndex := shr(224, calldataload(add(calldataPointer, 2)))
            }
            //increase calldataPointer to account for usage of 6 bytes
            calldataPointer += 6;
            //verify monotonic increase of bin indices
            require(
                currentBinIndex == type(uint32).max ||
                    nextBinIndex > currentBinIndex,
                "bad bin ordering - repeat bins?"
            );
            //update current bin index
            currentBinIndex = nextBinIndex;
            //256 single bit slots, initialized as zeroes
            //each bit is flipped if a signature is provided from the valid signatory for that slot, in the current bin
            uint256 claimsMadeInBin;
            //process a single bin
            while (sigsInCurrentBin > 0) {
                assembly {
                    //get the 32 bytes at calldataPointer, i.e. first half of signature data
                    r := calldataload(calldataPointer)
                    //get the 32 bytes at (calldataPointer + 32), i.e. second half of signature data
                    vs := calldataload(add(calldataPointer, 32))
                }
                signatory = ECDSA.recover(ferkleRoot, r, vs);
                //increase calldataPointer to account for length of signature
                calldataPointer += 64;
                operatorId = dlRegVW.getOperatorId(signatory);
                //16777216 is 2^24. this is the max bin index.
                require(
                    operatorId >> 8 == currentBinIndex,
                    "invalid sig bin index - improper sig ordering?"
                );
                //mask has a single '1' bit at sigIndex position
                mask = (1 << (operatorId % 256));
                //check that bit has not already been flipped
                require(
                    claimsMadeInBin & mask == 0,
                    "claim already made on this bit - repeat signature?"
                );
                //flip the bit to mark that 'sigIndex' has been claimed
                claimsMadeInBin = (claimsMadeInBin | mask);
                //fetch type of of operator
                uint8 operatorType = queryManager.getOperatorType(signatory);
                //increment totals based on operator type
                if (operatorType == 3) {
                    unchecked {
                        ++signedTotals.totalEigenSigners;
                        ++signedTotals.totalEthSigners;
                    }
                } else if (operatorType == 2) {
                    unchecked {
                        ++signedTotals.totalEthSigners;
                    }
                } else if (operatorType == 1) {
                    unchecked {
                        ++signedTotals.totalEigenSigners;
                    }
                } else {
                    revert("Operator not active");
                }
                //decrement counter of remaining signatures to check
                unchecked {
                    --sigsInCurrentBin;
                }
            }
            //update compressedSignatoryRecord variable
            compressedSignatoryRecord = keccak256(
                abi.encodePacked(
                    currentBinIndex,
                    claimsMadeInBin,
                    compressedSignatoryRecord
                )
            );
            //decrement numberOfBins counter at end of loop.
            unchecked {
                --numberOfBins;
            }
        }
        //return dumpNumber, ferkle root, eth and eigen that signed and a hash of the signatories
        return (
            dumpNumberToConfirm,
            ferkleRoot,
            signedTotals,
            compressedSignatoryRecord
        );
    }
}
