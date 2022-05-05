// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./DataLayrServiceManagerStorage.sol";
import "../RegistrationManagerBaseMinusRepository.sol";
import "../../libraries/BytesLib.sol";
import "../../libraries/SignatureCompaction.sol";


import "ds-test/test.sol";

abstract contract DataLayrSignatureChecker is
    DataLayrServiceManagerStorage
    , DSTest
{
    using BytesLib for bytes;
    uint256 constant MODULUS =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;
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
    uint32 numberOfNonSigners,
    bytes33[] compressedPubKeys of nonsigners
    uint32 apkIndex
    uint256[4] sigma
    */
    function checkSignatures(bytes calldata data)
        public
        returns (
            uint32 dumpNumberToConfirm,
            bytes32 headerHash,
            SignatoryTotals memory signedTotals,
            bytes32 compressedSignatoryRecord
        )
    {
        //dumpNumber corresponding to the headerHash
        //number of different signature bins that signatures are being posted from
        uint256 placeholder;
        assembly {
            //get the 32 bits immediately after the function signature and length encoding of bytes calldata type
            dumpNumberToConfirm := shr(224, calldataload(68))
            //get the 32 bytes immediately after the above
            headerHash := calldataload(72)
            //get the next 32 bits
            //numberOfNonSigners
            placeholder := shr(224, calldataload(104))
        }

        address dlvwAddress = address(repository.voteWeigher());
        IDataLayrVoteWeigher dlvw = IDataLayrVoteWeigher(dlvwAddress);
        //compressed public key
        bytes memory compressed;

        // we hav read (68 + 4 + 32 + 4 + 4) = 112 bytes
        uint256 pointer = 112;
        //TODO: DO WE NEED TO MAKE SURE INCREMENTAL PKHs?
        // uint256 prevPubkeyHashInt;

        uint256[12] memory input = [uint256(0),uint256(0),uint256(0),uint256(0),uint256(0),uint256(0),uint256(0),uint256(0),uint256(0),uint256(0),uint256(0),uint256(0)];

        SignatoryTotals memory sigTotals;
        //get totals
        signedTotals.ethStakeSigned = RegistrationManagerBaseMinusRepository(
            dlvwAddress
        ).totalEthStaked();
        signedTotals.totalEthStake = signedTotals.ethStakeSigned;
        signedTotals.eigenStakeSigned = RegistrationManagerBaseMinusRepository(
            dlvwAddress
        ).totalEigenStaked();
        signedTotals.totalEigenStake = signedTotals.eigenStakeSigned;

        for (uint i = 0; i < placeholder; ) {
            //load compressed pubkey into memory and the index in the stakes array
            uint256 stakeIndex;
            assembly {
                //next 33 bytes are compressed pubkey
                mstore(compressed, calldataload(pointer))
                mstore(add(compressed, 1), calldataload(add(pointer, 1)))
                // next 32 bits are stake index
                mstore(stakeIndex, shr(224, calldataload(add(pointer, 33))))
            }
            //decompress the pubkey
            {
                (uint256 pk_x, uint256 pk_y) = decompressPublicKey(compressed);
                input[2] = pk_x;
                input[3] = pk_y;
            }
            //get pubkeyHash, add it to nonSigners
            bytes32 pubkeyHash = keccak256(
                abi.encodePacked(input[2], input[3])
            );

            IDataLayrVoteWeigher.OperatorStake memory operatorStake = dlvw
                .getStakeFromPubkeyHashAndIndex(pubkeyHash, stakeIndex);

            require(
                operatorStake.dumpNumber <= dumpNumberToConfirm,
                "Operator stake index is too early"
            );

            require(
                operatorStake.nextUpdateDumpNumber == 0 ||
                    operatorStake.nextUpdateDumpNumber > dumpNumberToConfirm,
                "Operator stake index is too early"
            );

            //subtract validator stakes from totals
            signedTotals.ethStakeSigned -= operatorStake.ethStake;
            signedTotals.eigenStakeSigned -= operatorStake.eigenStake;

            // add new public key to non signer pk sum
            // input[2] = pk_x;
            // input[3] = pk_y;

            //overwrite first to indexes of input with new sum of non signer public keys
            assembly {
                if iszero(call(not(0), 0x06, 0, input, 0x80, input, 0x40)) {
                    revert(0, 0)
                }
                //increment pointer
                mstore(pointer, add(pointer, 37))
            }

            unchecked {
                ++i;
            }
        }

        assembly {
            //get next 32 bits
            //now its the apkIndex
            placeholder := shr(224, calldataload(108))
        }


        compressed = dlvw.getCorrectCompressedApk(
            placeholder,
            dumpNumberToConfirm
        );

        //get apk coordinates
        (uint256 apk_x, uint256 apk_y) = decompressPublicKey(compressed);

        //now we have the aggregate non signer key in input[0], input[1]
        //let's subtract it from the aggregate public key

        //negate aggregate non signer key
        input[1] = (MODULUS - input[1]) % MODULUS;
        //put apk in input for addition
        input[2] = apk_x;
        input[3] = apk_y;

        // add apk with negated agg non signer key, to get agg pk for verification
        assembly {
            if iszero(call(not(0), 0x06, 0, input, 0x80, input, 0x40)) {
                revert(0, 0)
            }
        }
        

        //now we check that
        //e(pk, H(m))e(-g1, sigma) == 1
        {
            uint256[4] memory hashOfMessage = hashToG2Point(
                headerHash
            );
            input[2] = hashOfMessage[0];
            input[3] = hashOfMessage[1];
            input[4] = hashOfMessage[2];
            input[5] = hashOfMessage[3];
        }
        //negated g1 coors
        input[6] = 1;
        input[7] = MODULUS - 2;

        assembly {
            //next in calldata are sigma_x1, sigma_x0, sigma_y1, sigma_y0
            mstore(add(input, 0x0100), calldataload(pointer))
            mstore(add(input, 0x0120), calldataload(add(pointer, 0x20)))
            mstore(add(input, 0x0140), calldataload(add(pointer, 0x40)))
            mstore(add(input, 0x0160), calldataload(add(pointer, 0x60)))
            //check the pairing
            //if incorrect, revert
            if iszero(call(not(0), 0x08, 0, input, 0x0180, input, 0x20)) {
                revert(0, 0)
            }
        }

        require(input[0] == 1, "Pairing unsuccessful");

        //sig is correct!!!

        //set compressedSignatoryRecord variable
        //used for payment fraud proofs
        compressedSignatoryRecord = keccak256(
            abi.encodePacked(
                // headerHash,
                dumpNumberToConfirm,
                signedTotals.ethStakeSigned,
                signedTotals.eigenStakeSigned
            )
        );

        //return dumpNumber, headerHash, eth and eigen that signed, and a hash of the signatories
        return (
            dumpNumberToConfirm,
            headerHash,
            signedTotals,
            compressedSignatoryRecord
        );
    }

    function decompressPublicKey(bytes memory compressed)
        public
        returns (uint256, uint256)
    {
        uint256 x;
        uint256 ySquared;
        uint256[] memory input = new uint256[](6);
        assembly {
            //x is the first 32 bytes of compressed
            x := mload(add(compressed, 0x20))
            x := mod(x, MODULUS)
            // ySquared = x^2 mod m
            ySquared := mulmod(x, x, MODULUS)
            // ySquared = x^3 mod m
            ySquared := mulmod(ySquared, x, MODULUS)
            // ySquared = x^3 + 3 mod m
            ySquared := addmod(ySquared, 3, MODULUS)
            //really the elliptic curve equation is y^2 = x^3 + 3 mod m
            //so we have y^2 stored, so let's find the sqrt

            // (y^2)^((MODULUS + 1)/4) = y
            // base of exponent is y
            mstore(
                add(input, 0x20),
                32 // y is 32 bytes long
            )
            // the exponent (MODULUS + 1)/4 is also 32 bytes long
            mstore(add(input, 0x40), 32)
            // MODULUS is 32 bytes long
            mstore(add(input, 0x60), 32)
            // base is y
            mstore(add(input, 0x80), ySquared)
            // exponent is (N + 1) / 4 = 0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52
            mstore(
                add(input, 0xA0),
                0xc19139cb84c680a6e14116da060561765e05aa45a1c72a34f082305b61f3f52
            )
            //MODULUS
            mstore(add(input, 0xC0), MODULUS)
            //store sqrt(y^2) = y in first element of input
            if iszero(
                call(
                    not(0),
                    0x05,
                    0,
                    add(input, 0x20),
                    0xE0,
                    add(input, 0x20),
                    0x20
                )
            ) {
                revert(0, 0)
            }
        }

        //use 33rd byte as toggle for the sign of sqrt
        //because y and -y are both solutions
        if (compressed[32] != 0) {
            input[0] = MODULUS - input[0];
        }
        return (x, input[0]);
    }

    function hashToG2Point(bytes32 msg)
        public
        returns (uint256[4] memory)
    {
        //HashToCurveG2Svdw("jeffreyisdalabstaman")
        uint256[4] memory point;
        point[
            0
        ] = 14335504872549532354210489828671972911333347940534076142795111812609903378108;
        point[
            1
        ] = 15548973838770842196102442698708122006189018193868154757846481038796366125273;
        point[
            2
        ] = 19822981108166058814837087071162475941148726886187076297764129491697321004944;
        point[
            3
        ] = 21654797034782659092642090020723114658730107139270194997413654453096686856286;
        return point;
    }
}
