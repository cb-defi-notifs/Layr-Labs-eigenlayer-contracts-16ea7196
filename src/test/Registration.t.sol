// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "./RevertTestHelper.t.sol";
import "../contracts/libraries/BytesLib.sol";

contract RegistrationTests is RevertTestHelper {
    using BytesLib for bytes;

    function testBLSRegistration() public {
        emit log_address(sample_registrant);

        bytes memory data = abi.encodePacked(registrationData[0]);
        cheats.startPrank(signers[0]);
        blsPkCompendium.registerBLSPublicKey(data);
        cheats.stopPrank();
    }

    function testRegisterPublicKeyTwice(uint8 operatorIndex) public {
        cheats.assume(operatorIndex < registrationData.length);
        cheats.startPrank(signers[operatorIndex]);
        //try to register the same pubkey twice
        pubkeyCompendium.registerBLSPublicKey(registrationData[operatorIndex]);
        cheats.expectRevert(
            "BLSPublicKeyRegistry.registerBLSPublicKey: operator already registered pubkey"
        );
        pubkeyCompendium.registerBLSPublicKey(registrationData[operatorIndex]);
    }

    function testRegisterForDataLayrWhileAlreadyActive(
        uint8 operatorIndex,
        uint256 ethAmount,
        uint256 eigenAmount
    ) public {
        //TODO: @sidu28 why doesn't fuzzing work here?
        cheats.assume(operatorIndex < registrationData.length);
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);
        uint8 operatorType = 3;
        _testInitiateDelegationAndRegisterOperatorWithDataLayr(
            operatorIndex,
            operatorType,
            testSocket,
            eigenAmount,
            ethAmount
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

    function testRegisterForDataLayrWithNeitherQuorum(
        uint8 operatorIndex,
        uint256 ethAmount,
        uint256 eigenAmount
    ) public {
        cheats.assume(operatorIndex < registrationData.length);
        cheats.assume(ethAmount > 0 && ethAmount < 1e18);
        cheats.assume(eigenAmount > 0 && eigenAmount < 1e18);
        uint8 noQuorumOperatorType = 0;
        _testShouldRevertRegisterOperatorWithDataLayr(
            operatorIndex,
            noQuorumOperatorType,
            testSocket,
            eigenAmount,
            ethAmount,
            "RegistryBase._registrationStakeEvaluation: Must register as at least one type of validator"
        );
    }
}
