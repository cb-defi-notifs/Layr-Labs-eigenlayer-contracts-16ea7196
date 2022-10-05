// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./TestHelper.t.sol";
import "../contracts/libraries/BytesLib.sol";

contract RegistrationTests is TestHelper {
    using BytesLib for bytes;

    function testBLSRegistration(
        uint8 operatorIndex,
        uint256 ethAmount, 
        uint256 eigenAmount
    ) fuzzedOperatorIndex(operatorIndex) public {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);
        
        uint8 operatorType = 3;
        (
            uint256 amountEthStaked, 
            uint256 amountEigenStaked
        ) = _testInitiateDelegation(
                operatorIndex,
                eigenAmount,
                ethAmount
            );

        _testRegisterBLSPubKey(operatorIndex);
        bytes32 hashofPk = keccak256(
                              abi.encodePacked(
                                uint256(bytes32(registrationData[operatorIndex].slice(32,32))),
                                uint256(bytes32(registrationData[operatorIndex].slice(0,32))),
                                uint256(bytes32(registrationData[operatorIndex].slice(96,32))),
                                uint256(bytes32(registrationData[operatorIndex].slice(64,32)))
                              )
                            );
        require(pubkeyCompendium.operatorToPubkeyHash(signers[operatorIndex]) == hashofPk, "hash not stored correctly");
        require(pubkeyCompendium.pubkeyHashToOperator(hashofPk) == signers[operatorIndex], "hash not stored correctly");

        {
            uint96 ethStakedBefore = dlReg.getTotalStakeFromIndex(dlReg.getLengthOfTotalStakeHistory()-1).firstQuorumStake;
            uint96 eigenStakedBefore = dlReg.getTotalStakeFromIndex(dlReg.getLengthOfTotalStakeHistory()-1).secondQuorumStake;
            _testRegisterOperatorWithDataLayr(
                operatorIndex,
                operatorType,
                testSocket
            );

            uint256 numOperators = dlReg.numOperators();
            require(dlReg.operatorList(numOperators-1) == signers[operatorIndex], "operatorList not updated");

        
            uint96 ethStakedAfter = dlReg.getTotalStakeFromIndex(dlReg.getLengthOfTotalStakeHistory()-1).firstQuorumStake;
            uint96 eigenStakedAfter = dlReg.getTotalStakeFromIndex(dlReg.getLengthOfTotalStakeHistory()-1).secondQuorumStake;


            require(ethStakedAfter - ethStakedBefore == amountEthStaked, "eth quorum staked value not updated correctly");
            require(eigenStakedAfter - eigenStakedBefore == amountEigenStaked, "eigen quorum staked value not updated correctly");
        }
    }

    function testRegisterPublicKeyTwice(uint8 operatorIndex) fuzzedOperatorIndex(operatorIndex) public {
        cheats.startPrank(signers[operatorIndex]);
        //try to register the same pubkey twice
        pubkeyCompendium.registerBLSPublicKey(registrationData[operatorIndex]);
        cheats.expectRevert(
            "BLSPublicKeyCompendium.registerBLSPublicKey: operator already registered pubkey"
        );
        pubkeyCompendium.registerBLSPublicKey(registrationData[operatorIndex]);
    }

    function testRegisterWhileAlreadyActive(
        uint8 operatorIndex, 
        uint256 ethAmount, 
        uint256 eigenAmount
    ) fuzzedOperatorIndex(operatorIndex) public {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);
        
        uint8 operatorType = 3;
        _testInitiateDelegation(
            operatorIndex,
            eigenAmount,
            ethAmount
        );
        _testRegisterBLSPubKey(
            operatorIndex
        );
        _testRegisterOperatorWithDataLayr(
            operatorIndex,
            operatorType,
            testSocket
        );
        cheats.startPrank(signers[operatorIndex]);

        //try to register after already registered
        cheats.expectRevert(
            "RegistryBase._registrationStakeEvaluation: Operator is already registered"
        );
        dlReg.registerOperator(
            3,
            bytes32(0),
            registrationData[operatorIndex].slice(0, 128),
            testSocket
        );
        cheats.stopPrank();
    }

    // function testRegisterWhileAlreadyActive(uint8 operatorIndex, uint256 ethAmount, uint256 eigenAmount) public {
    //     cheats.assume(operatorIndex < registrationData.length);
    //     cheats.assume(ethAmount > 0 && ethAmount < 1e18);
    //     cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);
    //     _testInitiateDelegationAndRegisterOperatorWithDataLayr(operatorIndex, eigenAmount, ethAmount);
    //     cheats.startPrank(signers[operatorIndex]);
    //     //try to register after already registered
    //     cheats.expectRevert("RegistryBase._registrationStakeEvaluation: Operator is already registered");
    //     dlReg.registerOperator(3, testEphemeralKey, registrationData[operatorIndex].slice(0, 128), testSocket);
    //     cheats.stopPrank();
    // }

    //Test that when operator tries to register with DataLayr 
    // with a public key that they haven't registered in the BLSPublicKeyCompendium, it fails
    function testOperatorDoesNotOwnPublicKey(
        uint8 operatorIndex, 
        uint256 ethAmount, 
        uint256 eigenAmount
    ) fuzzedOperatorIndex(operatorIndex) public {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);

        uint8 operatorType = 3;
        _testInitiateDelegation(
            operatorIndex,
            eigenAmount,
            ethAmount
        );
        //registering the operator without having registered their BLS public key
        cheats.expectRevert(bytes("BLSRegistry._registerOperator: operator does not own pubkey"));

        _testRegisterOperatorWithDataLayr(
            operatorIndex,
            operatorType,
            testSocket
        );
    } 

    function testRegisterForDataLayrWithNeitherQuorum(
        uint8 operatorIndex,
        uint256 ethAmount,
        uint256 eigenAmount
    ) fuzzedOperatorIndex(operatorIndex) public {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);
        uint8 noQuorumOperatorType = 0;

        _testInitiateDelegation(
            operatorIndex,
            eigenAmount,
            ethAmount
        );
        _testRegisterBLSPubKey(
            operatorIndex
        );
        cheats.expectRevert(bytes("RegistryBase._registrationStakeEvaluation: Must register as at least one type of validator"));
        _testRegisterOperatorWithDataLayr(
            operatorIndex,
            noQuorumOperatorType,
            testSocket
        );
    }

    function testRegisterWithoutEnoughQuorumStake(
        uint8 operatorIndex
    ) fuzzedOperatorIndex(operatorIndex) public {
        _testRegisterBLSPubKey(
            operatorIndex
        );

        uint8 operatorType = 1;
        cheats.expectRevert(bytes("RegistryBase._registrationStakeEvaluation: Must register as at least one type of validator"));
        _testRegisterOperatorWithDataLayr(operatorIndex, operatorType, testSocket);
        
        operatorType = 2;
        cheats.expectRevert(bytes("RegistryBase._registrationStakeEvaluation: Must register as at least one type of validator"));
                _testRegisterOperatorWithDataLayr(operatorIndex, operatorType, testSocket);

        operatorType = 3;
        cheats.expectRevert(bytes("RegistryBase._registrationStakeEvaluation: Must register as at least one type of validator"));
        _testRegisterOperatorWithDataLayr(operatorIndex, operatorType, testSocket);
    }


    //Test if aggregate PK doesn't change when registered with 0 pub key
    function testRegisterWithZeroPubKey(
        uint8 operatorIndex,
        uint256 ethAmount,
        uint256 eigenAmount
    ) fuzzedOperatorIndex(operatorIndex) public {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);

        bytes memory zeroData = hex"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        address operator = signers[operatorIndex];
        uint8 operatorType = 3;
        bytes32 apkHashBefore = dlReg.apkHashes(dlReg.getApkHashesLength()-1);
        emit log_named_bytes32("apkHashBefore", apkHashBefore);

        _testInitiateDelegation(
            operatorIndex,
            eigenAmount,
            ethAmount
        );
        cheats.startPrank(operator);
        //whitelist the dlsm to slash the operator
        slasher.allowToSlash(address(dlsm));
        pubkeyCompendium.registerBLSPublicKey(zeroData);

        cheats.expectRevert(bytes("BLSRegistry._registerOperator: Cannot register with 0x0 public key"));
        dlReg.registerOperator(operatorType, testEphemeralKey, zeroData, testSocket);
        cheats.stopPrank(); 
    }

    //test for registering without slashing opt in
    function testRegisterWithoutSlashingOptIn(
        uint8 operatorIndex,
        uint256 ethAmount,
        uint256 eigenAmount
     ) fuzzedOperatorIndex(operatorIndex) public {
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18); 

        uint8 operatorType = 3;

        _testInitiateDelegation(
            operatorIndex,
            eigenAmount,
            ethAmount
        );

        cheats.startPrank(signers[operatorIndex]);
        pubkeyCompendium.registerBLSPublicKey(registrationData[operatorIndex]);
        cheats.stopPrank();

        cheats.expectRevert(bytes("RegistryBase._addRegistrant: operator must be opted into slashing by the serviceManager"));
        _testRegisterOperatorWithDataLayr(
            operatorIndex,
            operatorType,
            testSocket
        );
     }

    // function testRegisteringWithSamePubKeyAsAggPubKey(
    //     uint8 operatorIndex,
    //     uint256 ethAmount,
    //     uint256 eigenAmount
    //  ) fuzzedOperatorIndex(operatorIndex) public {
    //     cheats.assume(ethAmount > 0 && ethAmount < 1e18);
    //     cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);
    //     uint256[4] memory prevAPK;
    //     prevAPK[0] = dlReg.apk(0);
    //     prevAPK[1] = dlReg.apk(1);
    //     prevAPK[2] = dlReg.apk(2);
    //     prevAPK[3] = dlReg.apk(3);
    //     bytes memory packedAPK = abi.encodePacked(
    //                                 bytes32(prevAPK[0]),
    //                                 bytes32(prevAPK[1]),
    //                                 bytes32(prevAPK[2]),
    //                                 bytes32(prevAPK[3])
    //                                 );
        
    //     uint8 operatorType = 3;

    //     _testInitiateDelegation(
    //         operatorIndex,
    //         eigenAmount,
    //         ethAmount
    //     );
    //     cheats.startPrank(signers[operatorIndex]);
    //     pubkeyCompendium.registerBLSPublicKey(packedAPK);

    
    //     dlReg.registerOperator(operatorType, testEphemeralKey, packedAPK, testSocket);
    //     cheats.stopPrank();
    //  }
}
