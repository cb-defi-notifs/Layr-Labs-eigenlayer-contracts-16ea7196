// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../libraries/BeaconChainProofs.sol";
import "../libraries/BytesLib.sol";
import "../libraries/Endian.sol";
import "../interfaces/IETHPOSDeposit.sol";
import "../interfaces/IEigenPodManager.sol";
import "../interfaces/IEigenPod.sol";
import "../interfaces/IBeaconChainETHReceiver.sol";

import "forge-std/Test.sol";

/**
 * @title The implementation contract used for restaking beacon chain ETH on EigenLayer 
 * @author Layr Labs, Inc.
 * @notice The main functionalities are:
 * - creating new validators with their withdrawal credentials pointed to this contract
 * - proving from beacon chain state roots that withdrawal credentials are pointed to this contract
 * - proving from beacon chain state roots the balances of validators with their withdrawal credentials
 *   pointed to this contract
 * - updating aggregate balances in the EigenPodManager
 * - withdrawing eth when withdrawals are initiated
 */
contract EigenPod is IEigenPod, Initializable , DSTest{
    using BytesLib for bytes;

    //TODO: change this to constant in prod
    IETHPOSDeposit immutable ethPOS;

    IEigenPodManager public eigenPodManager;


    address public podOwner;
    /// @notice this is a mapping of validator keys to a Validator struct which holds info about the validator and their balances
    mapping(bytes32 => Validator) public validators;

    modifier onlyEigenPodManager {
        require(msg.sender == address(eigenPodManager), "EigenPod.InvestmentManager: not eigenPodManager");
        _;
    }


    constructor(IETHPOSDeposit _ethPOS) {
        ethPOS = _ethPOS;
        //TODO: uncomment for prod
        //_disableInitializers();
    }

    function initialize(IEigenPodManager _eigenPodManager, address _podOwner) external initializer {
        eigenPodManager = _eigenPodManager;
        podOwner = _podOwner;
        // emit log("HEHHE");
    }

    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable onlyEigenPodManager {
        // stake on ethpos
        ethPOS.deposit{value : msg.value}(pubkey, podWithdrawalCredentials(), signature, depositDataRoot);
    }

    /**
    * @notice This function verifies that the withdrawal credentials of the podOwner are pointed to
    * this contract.  It verifies the provided proof from the validator against the beacon chain state
    * root.
    * @param pubkey is the BLS public key for the validator.
    * @param proofs is
    * @param validatorFields are the fields of the "Validator Container", refer to consensus specs 
    * for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
     */
    function verifyCorrectWithdrawalCredentials(
        bytes calldata pubkey, 
        bytes calldata proofs, 
        bytes32[] calldata validatorFields
    ) external {
        //TODO: tailor this to production oracle
        bytes32 beaconStateRoot = eigenPodManager.getBeaconChainStateRoot();
        // get merklizedPubkey: https://github.com/prysmaticlabs/prysm/blob/de8e50d8b6bcca923c38418e80291ca4c329848b/beacon-chain/state/stateutil/sync_committee.root.go#L45
        bytes32 merklizedPubkey = sha256(abi.encodePacked(pubkey, bytes16(0)));

        require(validators[merklizedPubkey].status == VALIDATOR_STATUS.INACTIVE, "EigenPod.verifyCorrectWithdrawalCredentials: Validator not inactive");
        //verify validator proof
        emit log("JHJSHS");
        verifyValidatorFields(
            beaconStateRoot,
            proofs,
            validatorFields
        );
            emit log_named_bytes32("pod", podWithdrawalCredentials().toBytes32(0));
        //require that the first field is the merkleized pubkey
        require(validatorFields[0] == merklizedPubkey, "EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for provided pubkey");
        require(validatorFields[1] == podWithdrawalCredentials().toBytes32(0), "EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for this EigenPod");
        //convert the balance field from 8 bytes of little endian to uint64 big endian 💪
        uint64 validatorBalance = Endian.fromLittleEndianUint64(validatorFields[2]);
        //update validator balance
        validators[merklizedPubkey].balance = validatorBalance;
        validators[merklizedPubkey].status = VALIDATOR_STATUS.ACTIVE;
        //update manager total balance for this pod
        //need to subtract zero and add the proven balance

        emit log_named_address("this address", address(this));

        eigenPodManager.updateBeaconChainBalance(podOwner, 0, validatorBalance);
        eigenPodManager.depositBeaconChainETH(podOwner, validatorBalance);
    }

    function verifyBalanceUpdate(
        bytes calldata pubkey, 
        bytes calldata proofs, 
        bytes32[] calldata validatorFields
    ) external {
        //TODO: tailor this to production oracle
        bytes32 beaconStateRoot = eigenPodManager.getBeaconChainStateRoot();
        // get merklizedPubkey
        bytes32 merklizedPubkey = sha256(abi.encodePacked(pubkey, bytes16(0)));
        require(validators[merklizedPubkey].status == VALIDATOR_STATUS.ACTIVE, "EigenPod.verifyBalanceUpdate: Validator not active");
        //verify validator proof
        BeaconChainProofs.verifyValidatorFields(
            beaconStateRoot,
            proofs,
            validatorFields
        );
        //require that the first field is the merkleized pubkey
        require(validatorFields[0] == merklizedPubkey, "EigenPod.verifyBalanceUpdate: Proof is not for provided pubkey");
        //convert the balance field from 8 bytes of little endian to uint64 big endian 💪
        uint64 validatorBalance = Endian.fromLittleEndianUint64(validatorFields[2]);
        emit log_named_uint("validatorBalance", validatorBalance);
        uint64 prevValidatorBalance = validators[merklizedPubkey].balance;
        //update validator balance
        validators[merklizedPubkey].balance = validatorBalance;
        //update manager total balance for this pod
        //need to subtract previous proven balance and add the current proven balance
        eigenPodManager.updateBeaconChainBalance(podOwner, prevValidatorBalance, validatorBalance);
    }

    /// @notice Transfers ether balance of this contract to the specified recipeint address
    function withdrawBeaconChainETH(
        address recipient,
        uint256 amount
    )
        external
        onlyEigenPodManager
    {
        //transfer ETH directly from pod to msg.sender 
        IBeaconChainETHReceiver(recipient).receiveBeaconChainETH{value: amount}();
    }

    // INTERNAL FUNCTIONS
    function podWithdrawalCredentials() internal view returns(bytes memory) {
        return abi.encodePacked(bytes1(uint8(1)), bytes11(0), address(this));
    }

    function verifyValidatorFields(
        bytes32 beaconStateRoot, 
        bytes calldata proofs, 
        bytes32[] calldata validatorFields
    ) internal {
        require(validatorFields.length == 2**BeaconChainProofs.VALIDATOR_FIELD_TREE_HEIGHT, "EigenPod.verifyValidatorFields: Validator fields has incorrect length");
        uint256 pointer;
        bool valid;
        //verify that the validatorTreeRoot is within the top level beacon state tree
        bytes32 validatorTreeRoot = proofs.toBytes32(0);

        emit log_named_bytes32("validatorTreeRoot", validatorTreeRoot);
        emit log_named_bytes32("beaconStateRoot", beaconStateRoot);
        //offset 32 bytes for validatorTreeRoot
        pointer += 32;
        emit log_named_bytes("beacon proofs",  proofs.slice(pointer, 32 * BeaconChainProofs.BEACON_STATE_FIELD_TREE_HEIGHT));
        valid = Merkle.checkMembershipSha256(
            validatorTreeRoot,
            BeaconChainProofs.VALIDATOR_TREE_ROOT_INDEX,
            beaconStateRoot,
            proofs.slice(pointer, 32 * BeaconChainProofs.BEACON_STATE_FIELD_TREE_HEIGHT)
        );
        require(valid, "EigenPod.verifyValidatorFields: Invalid validator tree root from beacon state proof");
        //offset the length of the beacon state proof
        pointer += 32 * BeaconChainProofs.BEACON_STATE_FIELD_TREE_HEIGHT;
        // verify the proof of the validator metadata root against the merkle root of the entire validator tree
        //https://github.com/prysmaticlabs/prysm/blob/de8e50d8b6bcca923c38418e80291ca4c329848b/beacon-chain/state/stateutil/validator_root.go#L26
        bytes32 validatorRoot = proofs.toBytes32(pointer);
        //make sure that the provided validatorFields are consistent with the proven leaf
        require(validatorRoot == Merkle.merkleizeSha256(validatorFields), "EigenPod.verifyValidatorFields: Invalid validator fields");
        //offset another 32 bytes for the length of the validatorRoot
        pointer += 32;
        //verify that the validatorRoot is within the validator tree
        emit log("YOOOO");
        emit log_named_bytes32("validatorRoot", validatorRoot);
        emit log_named_uint("index", proofs.toUint256(pointer));
        emit log_named_bytes32("validatorTreeRoot", validatorTreeRoot);
        valid = checkMembershipSha256(
            validatorRoot,
            proofs.toUint256(pointer), //validatorIndex
            validatorTreeRoot,
            proofs.slice(pointer + 32, 32 * 41)
        );
        require(valid, "EigenPod.verifyValidatorFields: Invalid validator root from validator tree root proof");
    }

    function checkMembershipSha256(
        bytes32 leaf,
        uint256 index,
        bytes32 rootHash,
        bytes memory proof
    ) internal  returns (bool) {
        require(proof.length % 32 == 0, "Invalid proof length");
        uint256 proofHeight = proof.length / 32;
        // Proof of size n means, height of the tree is n+1.
        // In a tree of height n+1, max #leafs possible is 2 ^ n
        require(index < 2 ** proofHeight, "Leaf index is too big");

        bytes32 proofElement;
        bytes32 computedHash = leaf;
        for (uint256 i = 32; i <= proof.length; i += 32) {
            assembly {
                proofElement := mload(add(proof, i))
            }

            if (index % 2 == 0) {
                computedHash = sha256(
                    abi.encodePacked(computedHash, proofElement)
                );
                
            } else {
                
                computedHash = sha256(
                    abi.encodePacked(proofElement, computedHash)
                );
               
            }

            index = index / 2;
        }
emit log_named_bytes32("HASH", computedHash);
        return computedHash == rootHash;
    }
}