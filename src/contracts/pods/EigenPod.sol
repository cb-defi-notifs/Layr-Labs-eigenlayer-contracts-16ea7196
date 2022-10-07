// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "../libraries/BeaconChainProofs.sol";
import "../libraries/BytesLib.sol";
import "../interfaces/IETHPOSDeposit.sol";
import "../interfaces/IEigenPodFactory.sol";
import "../interfaces/IEigenPod.sol";

contract EigenPod is IEigenPod, Initializable {
    using BytesLib for bytes;

    struct Validator {
        VALIDATOR_STATUS status;
        uint64 stake; //stake in gwei
    }

    enum VALIDATOR_STATUS {
        INACTIVE, //doesnt exist
        INITIALIZED, //staked on ethpos but withdrawal credentials not proven
        STAKED //staked on ethpos and withdrawal credentials are pointed
    }

    //TODO: change this to constant in prod
    IETHPOSDeposit immutable ethPOS;

    IEigenPodFactory public eigenPodFactory;
    address public owner;
    mapping(bytes32 => Validator) public validators;

    constructor(IETHPOSDeposit _ethPOS) {
        ethPOS = _ethPOS;
        _disableInitializers();
    }

    function initialize(IEigenPodFactory _eigenPodFactory, address _owner) external initializer {
        eigenPodFactory = _eigenPodFactory;
        owner = _owner;
    }

    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable {
        // get merklizedPubkey: https://github.com/prysmaticlabs/prysm/blob/de8e50d8b6bcca923c38418e80291ca4c329848b/beacon-chain/state/stateutil/sync_committee.root.go#L45
        bytes32 merklizedPubkey = sha256(abi.encodePacked(pubkey, bytes16(0)));
        // stake on ethPOS
        ethPOS.deposit{value : msg.value}(pubkey, podWithdrawalCredentials(), signature, depositDataRoot);
        //if not previously known validator, then update status
        if(validators[merklizedPubkey].status == VALIDATOR_STATUS.INACTIVE) {
            validators[merklizedPubkey].status = VALIDATOR_STATUS.INITIALIZED;
        }
    }

    function proveCorrectWithdrawalCredentials(
        bytes calldata pubkey, 
        bytes32 beaconStateRoot, 
        bytes calldata proofs, 
        bytes32[] calldata validatorFields
    ) external {
        //TODO: verify the beaconStateRoot is consistent with oracle

        // get merklizedPubkey
        bytes32 merklizedPubkey = sha256(abi.encodePacked(pubkey, bytes16(0)));
        require(validators[merklizedPubkey].status == VALIDATOR_STATUS.INITIALIZED, "EigenPod.proveCorrectWithdrawalCredentials: Validator not initialized");
        //verify validator proof
        BeaconChainProofs.verifyValidatorFields(
            beaconStateRoot,
            proofs,
            validatorFields
        );
        //require that the first field is the merkleized pubkey
        require(validatorFields[0] == merklizedPubkey, "EigenPod.proveCorrectWithdrawalCredentials: Proof is not for provided pubkey");
        require(validatorFields[1] == podWithdrawalCredentials().toBytes32(0), "EigenPod.proveCorrectWithdrawalCredentials: Proof is not for this EigenPod");
        //convert the balance field from 8 bytes of little endian to uint256 big endian 💪
        uint64 validatorStake = fromLittleEndianUint64(validatorFields[2]);
        //update validator stake
        validators[merklizedPubkey].stake = validatorStake;
        validators[merklizedPubkey].status == VALIDATOR_STATUS.STAKED;
        //update factory total stake for this pod
        //need to subtract zero and add the proven balance
        eigenPodFactory.updateBeaconChainStake(owner, 0, validatorStake);
    }

    function verifyStakeUpdate(
            bytes calldata pubkey, 
            bytes32 beaconStateRoot, 
            bytes calldata proofs, 
            bytes32[] calldata validatorFields
    ) external {
        //TODO: verify the beaconStateRoot is consistent with oracle

        // get merklizedPubkey
        bytes32 merklizedPubkey = sha256(abi.encodePacked(pubkey, bytes16(0)));
        require(validators[merklizedPubkey].status == VALIDATOR_STATUS.STAKED, "EigenPod.proveCorrectWithdrawalCredentials: Validator not staked");
        //verify validator proof
        BeaconChainProofs.verifyValidatorFields(
            beaconStateRoot,
            proofs,
            validatorFields
        );
        //require that the first field is the merkleized pubkey
        require(validatorFields[0] == merklizedPubkey, "EigenPod.proveCorrectWithdrawalCredentials: Proof is not for provided pubkey");
        //convert the balance field from 8 bytes of little endian to uint64 big endian 💪
        uint64 validatorStake = fromLittleEndianUint64(validatorFields[2]);
        uint64 prevValidatorStake = validators[merklizedPubkey].stake;
        //update validator stake
        validators[merklizedPubkey].stake = validatorStake;
        //update factory total stake for this pod
        //need to subtract previous proven balance and add the current proven balance
        eigenPodFactory.updateBeaconChainStake(owner, prevValidatorStake, validatorStake);
    }

    function podWithdrawalCredentials() internal view returns(bytes memory) {
        return abi.encodePacked(bytes1(uint8(1)), bytes11(0), address(this));
    }

    //copied from https://etherscan.io/address/0x3FEFc5A4B1c02f21cBc8D3613643ba0635b9a873#code, thanks
    function fromLittleEndianUint64(bytes32 num) internal pure returns (uint64) {
        uint64 v = uint64(uint256(num >> 192));
        //if we number the bytes (1, 2, 3, 4, 5, 6, 7, 8)
        v = ((v & 0x00ff00ff00ff00ff) << 8) | ((v & 0xff00ff00ff00ff00) >> 8);
        // (2, 0, 4, 0, 6, 0, 8, 0) | (0, 1, 0, 3, 0, 5, 0, 7)
        // = (2, 1, 4, 3, 6, 5, 8, 7)
        v = ((v & 0x0000ffff0000ffff) << 16) | ((v & 0xffff0000ffff0000) >> 16);
        // (4, 3, 0, 0, 8, 7, 0, 0) | (0, 0, 2, 1, 0, 0, 6, 5)
        // = (4, 3, 2, 1, 8, 7, 6, 5)
        // then
        // = (8, 7, 6, 5, 4, 3, 2, 1)
        return (v << 32) | (v >> 32);
    }

}