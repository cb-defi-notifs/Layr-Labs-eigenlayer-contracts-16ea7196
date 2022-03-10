// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract EfficientSignatureCheck {
    // Data Layr Nodes
    struct Registrant {
        string socket; // how people can find it
        uint32 id; // id is always unique
        uint256 index; // corresponds to registrantList
        uint32 from;
        uint32 to;
        bool active; //bool
        uint256 stake;
    }
    // Register, everyone is active in the list
    mapping(address => Registrant) public registry;

/*
	//mapping from valid signatories to positions in a bitmap. a position of '0' (the default) indicates an invalid signatory
	//signatoryIndices[user] / 16777216 = user bin. signatoryIndices[user] % 256 = user index inside of that bin
	mapping(address => uint256) internal signatoryIndices;
*/
	

//NOTE: this assumes length 64 signatures
//TODO: sanity check on calldata length?
//TODO: do math instead of updating calldataPointer variable?
//TODO: better storage for signatoryIndices -- currently need 32 bits, which can be part of a struct
//TODO: check on sigHash
//TODO: write some data
//TODO: possibly checks on bins. e.g. 1+ sig per bin for some bins, > x for some bins, etc.
//TODO: multiple indices for different things? e.g. one for ETH, one for NFGTs?
	function checkSignatures() external returns (uint256) {
		//number of different signature bins that signatures are being posted from
        uint16 numberOfBins;
        //number of signatures contained in the bin currently being processed
        uint16 sigsInCurrentBin;
        //index of current bin of signatures being processed
        uint32 currentBinIndex;
        //signed data
		bytes32 sigHash;
		//keeps track of total number the valid signatures in this dump
		uint256 totalValidSignatures;
        assembly {
        	//get the 16 bits immediately after the function signature
            numberOfBins  := shr(240, calldataload(4))
        }
        assembly {
        	//get the 32 bytes immediately after the above
            sigHash  := calldataload(6)
        }

        //initialize at value that will be used in next calldataload
        uint32 calldataPointer = 38;
        //keeps track of the total number of bins that have been fully processed so far
        uint16 binsProcessed;
	    //transitory variables to be reused in loops
		bytes32 r;
		bytes32 vs;
		address signatory;
		//temporary variable used to gaurantee that binIndices are strictly increasing. prevents usage of duplicate bins
		uint32 nextBinIndex;
        //loop for each bin of signatures. ends once all bins have been processed
        while(binsProcessed < numberOfBins) {
        	//update sigsInBin and binIndex for next bin
	        assembly {
	        	//get the 16 bits at the current calldataPointer
	            sigsInCurrentBin  := shr(240, calldataload(calldataPointer))
	        	//get the 32 bits immediately after the 2 bytes for sigsInCurrentBin
	            nextBinIndex  := shr(224, calldataload(add(calldataPointer, 2)))
	        }
	        //increase calldataPointer to account for usage of 6 bytes
	        calldataPointer += 6;
	        //verify monotonic increase of bin indices
	        require(currentBinIndex == 0 || nextBinIndex > currentBinIndex, "bad bin ordering - repeat bins?");
	        //update current bin index
	        currentBinIndex = nextBinIndex;
			//256 single bit slots, initialized as zeroes
			//each bit is flipped if a signature is provided from the valid signatory for that slot, in the current bin
			uint256 claimsMadeInBin;
        	//process a single bin
        	for (uint16 i; i < sigsInCurrentBin; i++) {
	        	assembly {
	        		//get the 32 bytes at calldataPointer
	            	r  := calldataload(calldataPointer)
	        		//get the 32 bytes at (calldataPointer + 32)
	            	vs  := calldataload(add(calldataPointer, 32))
	        	}
				signatory = ECDSA.recover(sigHash, r, vs);
				//increase calldataPointer to account for length of signature
	        	calldataPointer += 64;
				uint32 index = registry[signatory].index;
				//uint256 binIndex = index / 16777216;
				//uint256 sigIndex = index % 256
				//16777216 is 2^24. this is the max bin index.
	        	require(index / 16777216 == currentBinIndex, "invalid sig bin index - improper sig ordering?");
	        	//mask has a single '1' bit at sigIndex position
	        	uint256 mask = (1 << (index % 256));
	        	//check that bit has not already been flipped
	        	require(claimsMadeInBin & mask == mask, "claim already made on this bit - repeat signature?");
	        	//flip the bit to mark that 'sigIndex' has been claimed
	        	claimsMadeInBin = (claimsMadeInBin | mask);
	        	//increment counter of valid signatures
	        	totalValidSignatures += 1;
        	}
	        //increase binsProcessed counter at end of loop        		
        	binsProcessed++;
        }
	}

	// struct Signature {
	// 	bytes32 content;
	// 	uint8 v;
	// 	bytes32 r;
	// 	bytes32 s;
	// }

	// //mapping from valid signatories to positions in a bitmap. a position of '0' (the default) indicates an invalid signatory
	// mapping(address => uint256) internal signatoryIndices;

	// function getBit(uint256 index) public view {
 //        uint256 claimedWordIndex = index / 256;
 //        uint256 claimedBitIndex = index % 256;
 //        uint256 claimedWord = claimedBitMap[claimedWordIndex];
 //        uint256 mask = (1 << claimedBitIndex);
 //        return claimedWord & mask == mask;
	// }

	// function checkSignatures(Signature[] calldata signatures) public view returns (uint256) {
	// 	uint256 totalValidSignatures;
	// 	uint256 totalBins = signatures / 256;
	// 	for (uint256 i; i <= signatures / 256; i++) {
	// 		//256 single bit slots. each one is flipped if a signature is provided from the valid signatory for that slot.
	// 		uint256 claimsMadeInBin;
	// 		uint256 signaturesToCheck = (signatures.length <= (i * 256 + 256)) ? (signatures.length - (i * 256)) : 256;
	// 		for (uint256 j; j < signaturesToCheck; i++) {
	// 			//TODO: check something about signed data. use better ecrecover logic.
	// 			address signatory = ecrecover(signatures[j + (i * 256)]);
	// 			uint256 index = signatoryIndices[signatory];
	//         	uint256 binIndex = index / 256;
	//         	require(binIndex == i, "invalid bin index");
	//         	uint256 sigIndex = index % 256;
	//         	//mask has a single '1' bit at sigIndex position
	//         	uint256 mask = (1 << sigIndex);
	//         	//check that bit has not already been flipped
	//         	require(claimsMadeInBin & mask == mask, "claim already made on this bit");
	//         	//flip the bit to mark that 'sigIndex' has been claimed
	//         	claimsMadeInBin = (claimsMadeInBin | mask);
	//         	totalValidSignatures += 1;
	// 		}
	// 	}
	// 	return totalValidSignatures;
	// }

		// bytes32 claimedBitmap;
		// for (uint256 i = 0; i < signatures.length; i++) {
		// 	address signatory = ecrecover(signatures[i]);
		// 	bytes32 signatoryIndex = signatoryIndices[signatory];
		// 	//actually length 24
  //       	bytes32 signatoryBlockIndex = signatoryIndex >> 8;
  //       	//actually length 8
  //       	bytes32 signatoryBitIndex = signatoryIndex << 24;
  //       	uint256 mask = (1 << signatoryBitIndex);
  //       	if (claimedBitmap & mask == mask){
  //       		claimedBitmap = (claimedBitmap | signatoryBlockIndex)
  //       	}
  //       	return 
  //       	claimedBitmap
		// }




}