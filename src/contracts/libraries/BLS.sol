import "ds-test/test.sol";

library BLS {
    // Field order
    uint256 constant MODULUS =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;

    // constructor() {

    // }

    function verifyBLSSigOfPubKeyHash(bytes calldata data)
        public
        returns (uint256, uint256)
    {
        uint256 offset = 68;
        //copy first 33 bytes of calldata after function sig to compressed public key
        bytes
            memory compressed = hex"000000000000000000000000000000000000000000000000000000000000000000";
        assembly {
            mstore(add(compressed, 0x20), calldataload(offset))
            mstore(add(compressed, 0x21), calldataload(add(offset, 1)))
        }

        (uint256 pk_x, uint256 pk_y) = decompressPublicKey(compressed);
        // e(-g1, sigma)e(pk, H(m)) == 1
        uint256[12] memory input;
        //calculate H(m)
        uint256[4] memory hashOfMessage = hashToG2Point(compressed);
        //negated g1 generator coordinates
        input[0] = 1;
        input[1] = MODULUS - 2;
        //next in calldata are sigma_x1, sigma_y1, sigma_x2, sigma_y2
        assembly {
            mstore(add(input, 0x40), calldataload(add(offset, 33)))
            mstore(add(input, 0x60), calldataload(add(offset, 65)))
            mstore(add(input, 0x80), calldataload(add(offset, 97)))
            mstore(add(input, 0xA0), calldataload(add(offset, 129)))
            //e(pk,H(m))
            mstore(add(input, 0xC0), pk_x)
            mstore(add(input, 0xE0), pk_y)
            //idk why tf its stored so far after reference
            mstore(add(input, 0x0100), mload(add(hashOfMessage, 0xA0)))
            mstore(add(input, 0x0120), mload(add(hashOfMessage, 0xC0)))
            mstore(add(input, 0x0140), mload(add(hashOfMessage, 0xE0)))
            mstore(add(input, 0x0160), mload(add(hashOfMessage, 0x0100)))
            //check the pairing
            if iszero(
                call(not(0), 0x08, 0, input, 0x0180, add(input, 0x20), 0x20)
            ) {
                revert(0, 0)
            }
        }

        require(input[1] == 1, "Pairing was unsuccessful");

        //return pk
        return (pk_x, pk_y);
    }

    // function register(bytes calldata, bytes calldata validatorKeySet) external {
    //     require(publicKeyHashes[msg.sender] == bytes32(0), "Already registered");
    //     uint256 offset = 0; //todo: fix this
    //     //copy first 33 bytes of calldata after function sig to compressed public key
    //     bytes memory compressed;
    //     assembly {
    //         mstore(compressed, calldataload(offset))
    //         mstore(add(compressed, 1), calldataload(add(offset, 1)))
    //     }
    //     (uint256 pk_x, uint256 pk_y) = decompressPublicKey(compressed);

    //     // e(g1, sigma)
    //     uint256[6] memory input;
    //     //g1 generator coordinates
    //     input[0] = 1;
    //     input[1] = 2;
    //     //next in calldata are sigma_x, sigma_y, result_x, result_y
    //     assembly {
    //         mstore(add(input, 0x40), calldataload(add(offset, 33)))
    //         mstore(add(input, 0x60), calldataload(add(offset, 65)))
    //         mstore(add(input, 0x80), calldataload(add(offset, 97)))
    //         mstore(add(input, 0xA0), calldataload(add(offset, 129)))
    //         //check the paring
    //         //if incorrect, revert
    //         if iszero(call(not(0), 0x07, 0, input, 0xC0, 0x0, 0x0)) {
    //             revert(0, 0)
    //         }
    //     }

    //     //e(pk, H(m))
    //     input[0] = pk_x;
    //     input[1] = pk_y;
    //     input[2] = REGISTRATION_MESSAGE_x;
    //     input[3] = REGISTRATION_MESSAGE_y;

    //     assembly {
    //         //check the paring
    //         //if incorrect, revert
    //         if iszero(call(not(0), 0x07, 0, input, 0xC0, 0x0, 0x0)) {
    //             revert(0, 0)
    //         }
    //     }

    //     //both pairings checked out, so signature is valid, and they can register!
    //     //store public key hash
    //     publicKeyHashes[msg.sender] = keccak256(abi.encodePacked(pk_x, pk_y));

    //     require(keccak256(validatorKeySet) == validatorKeySetHash, "validatorKeySet is incorrect");
    //     validatorKeySetHash = keccak256(abi.encodePacked(compressed, validatorKeySet));
    // }

    // function verifyAggregateSig(bytes calldata, bytes calldata validatorKeySet) external {
    //     require(keccak256(validatorKeySet) == validatorKeySetHash, "validatorKeySet is incorrect");
    //     uint256 offset = 0;//todo: fix this

    //     //first 32 bytes are number of signers
    //     uint256 numSigners;
    //     assembly {
    //         numSigners := calldataload(offset)
    //     }
    //     //points to beginning of keyset
    //     uint256 keySetOffset = offset + numSigners * 4 +10000; //todo: fix this
    //     uint256[6] memory input;
    //     uint256 pointer;
    //     uint256 prevPointer;
    //     bytes memory compressed;
    //     assembly {
    //         //next 32 bits point to signer index
    //         //point to keySetOffset + 33*index
    //         pointer := add(keySetOffset, mul(shr(calldataload(add(offset, 32)), 224), 33))
    //         mstore(compressed, calldataload(pointer))
    //         mstore(add(compressed, 1), calldataload(add(pointer, 31)))
    //     }
    //     //get first guys public key
    //     (uint256 pk_x, uint256 pk_y) = decompressPublicKey(compressed);
    //     input[0] = pk_x;
    //     input[1] = pk_y;
    //     prevPointer = pointer;
    //     for (uint i = 0; i < numSigners; i++) {
    //         assembly {
    //             //next 32 bits point to signer index
    //             //index is at offset + 32 + 4*i
    //             //point to keySetOffset + 33*index
    //             pointer := add(keySetOffset, mul(shr(calldataload(add(offset, add(32, mul(4, i)))), 224), 33))
    //             mstore(compressed, calldataload(pointer))
    //             mstore(add(compressed, 1), calldataload(add(pointer, 31)))
    //         }
    //         require(prevPointer < pointer, "Must keep pointing to higher indexes");
    //         (uint256 pk_x, uint256 pk_y) = decompressPublicKey(compressed);
    //         input[2] = pk_x;
    //         input[3] = pk_y;
    //         //add the points and overwrite the first point with the sum
    //         assembly {
    //             if iszero(call(not(0), 0x06, 0, input, 0x80, input, 0x40)) {
    //                 revert(0, 0)
    //             }
    //         }
    //     }
    //     //now the first 2 elements of input are the sum of the public keys, which is the agreggate public key

    //     //next in calldata are H(m)_x, H(m)_y, sigma_x, sigma_y, result_x, result_y
    //     assembly {
    //         mstore(add(input, 0x40), calldataload(sub(keySetOffset, 192)))
    //         mstore(add(input, 0x60), calldataload(sub(keySetOffset, 160)))
    //         mstore(add(input, 0x80), calldataload(add(offset, 64)))
    //         mstore(add(input, 0xA0), calldataload(add(offset, 32)))
    //         //check the paring
    //         //if incorrect, revert
    //         if iszero(call(not(0), 0x07, 0, input, 0xC0, 0x0, 0x0)) {
    //             revert(0, 0)
    //         }
    //     }

    //     //e(g1, sigma)
    //     input[0] = 1; //g1 generator coordinates
    //     input[1] = 2;
    //     assembly {
    //         mstore(add(input, 0x40), calldataload(sub(keySetOffset, 128)))
    //         mstore(add(input, 0x60), calldataload(sub(keySetOffset, 96)))
    //         //check the paring
    //         //if incorrect, revert
    //         if iszero(call(not(0), 0x07, 0, input, 0xC0, 0x0, 0x0)) {
    //             revert(0, 0)
    //         }
    //     }

    //     //yay! pairings checked out! we are signed baby
    // }

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

    function hashToG2Point(bytes memory msg)
        public
        returns (uint256[4] memory)
    {
        //HashToCurveG2Svdw("jeffreyisiceboxhouseman")
        uint256[] memory point = new uint256[](4);
        point[
            0
        ] = 9364298756309776628199387033821851750340471071075695617975235895891581663225;
        point[
            1
        ] = 4380710607657135460515851043751636390191957922713551572745261236748761161606;
        point[
            2
        ] = 6452696465875850474224218541043364493198210672553856085699676951205727203498;
        point[
            3
        ] = 4634267032819659129156207038151455671745731304073306463732527958120227233306;
    }
}
