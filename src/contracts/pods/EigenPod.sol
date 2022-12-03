// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../libraries/StructuredLinkedList.sol";
import "../libraries/BeaconChainProofs.sol";
import "../libraries/BytesLib.sol";
import "../libraries/Endian.sol";
import "../interfaces/IETHPOSDeposit.sol";
import "../interfaces/IEigenPodManager.sol";
import "../interfaces/IEigenPod.sol";
import "../interfaces/IBeaconChainETHReceiver.sol";

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
contract EigenPod is IEigenPod, Initializable {
    using BytesLib for bytes;

    uint256 private constant HEAD = 0;

    //TODO: change this to constant in prod
    IETHPOSDeposit immutable ethPOS;

    /// @notice The amount of eth, in gwei that is restaked per validator
    uint64 immutable REQUIRED_BALANCE_GWEI;

        /// @notice The amount of eth, in gwei that is restaked per validator
    uint256 immutable REQUIRED_BALANCE_WEI;

    /// @notice The amount of eth, in gwei that can be part of a partial withdrawal maximum
    uint64 immutable MAX_PARTIAL_WTIHDRAWAL_AMOUNT_GWEI;
    
    /// @notice The single InvestmentManager for EigenLayer
    IInvestmentManager immutable investmentManager;

    /// @notice The single EigenPodManager for EigenLayer
    IEigenPodManager public eigenPodManager;

    /// @notice The owner of this EigenPod
    address public podOwner;

    /// @notice this is a mapping of validator keys to a Validator struct containing pertinent info about the validator
    mapping(bytes32 => Validator) public validators;

    /// @notice the cumulative amount of proven full withdrawals until or at a certain block number on order of block number
    StructuredLinkedList.List public cumulativeFullWithdrawals;

    /// @notice the amount of execution layer ETH in this contract that is staked in EigenLayer (i.e. withdrawn from beaconchain but not EigenLayer), 
    /// it could have also been decremented from EigenLayer due to overcommitting balance
    uint256 public restakedExecutionLayerETH;

    /// @notice the excess balance from full withdrawals over RESTAKED_BALANCE_PER_VALIDATOR
    uint256 public withdrawableDueToExcess;

    /// @notice the total amount of eth withdrawn from EigenLayer on behalf of this pod
    uint256 public eigenLayerBeaconChainEthWithdrawn;

    /// @notice the total amount of eth slashable due to over committing to EigenLayer on behalf of this pod
    uint256 public slashableBalanceDueToOvercommitting;

    modifier onlyEigenPodManager {
        require(msg.sender == address(eigenPodManager), "EigenPod.onlyEigenPodManager: not eigenPodManager");
        _;
    }

    constructor(IETHPOSDeposit _ethPOS, uint256 _REQUIRED_BALANCE_WEI, uint64 _MAX_PARTIAL_WTIHDRAWAL_AMOUNT_GWEI, IInvestmentManager _investmentManager) {
        ethPOS = _ethPOS;
        REQUIRED_BALANCE_WEI = _REQUIRED_BALANCE_WEI;
        REQUIRED_BALANCE_GWEI = uint64(_REQUIRED_BALANCE_WEI / 1e9);
        MAX_PARTIAL_WTIHDRAWAL_AMOUNT_GWEI = _MAX_PARTIAL_WTIHDRAWAL_AMOUNT_GWEI;
        investmentManager = _investmentManager;
        _disableInitializers();
    }

    /// @notice Used to initialize the pointers to contracts crucial to the pod's functionality, in beacon proxy construction from EigenPodManager
    function initialize(IEigenPodManager _eigenPodManager, address _podOwner) external initializer {
        eigenPodManager = _eigenPodManager;
        podOwner = _podOwner;
    }

    /// @notice Called by EigenPodManager when the owner wants to create another validator.
    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable onlyEigenPodManager {
        // stake on ethpos
        require(msg.value == 32 ether, "EigenPod.stake: must initially stake for any validator with 32 ether");
        ethPOS.deposit{value : msg.value}(pubkey, podWithdrawalCredentials(), signature, depositDataRoot);
    }

    /**
     * @notice This function verifies that the withdrawal credentials of the podOwner are pointed to
     * this contract.  It verifies the provided proof from the validator against the beacon chain state
     * root.
     * @param pubkey is the BLS public key for the validator.
     * @param proofs is the bytes that prove the validator's metadata against a beacon state root
     * @param validatorFields are the fields of the "Validator Container", refer to consensus specs 
     * for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
     */
    function verifyCorrectWithdrawalCredentials(
        bytes calldata pubkey, 
        bytes calldata proofs, 
        bytes32[] calldata validatorFields
    ) external {
        // TODO: tailor this to production oracle
        bytes32 beaconStateRoot = eigenPodManager.getBeaconChainStateRoot();

        // get merklizedPubkey: https://github.com/prysmaticlabs/prysm/blob/de8e50d8b6bcca923c38418e80291ca4c329848b/beacon-chain/state/stateutil/sync_committee.root.go#L45
        bytes32 merklizedPubkey = sha256(abi.encodePacked(pubkey, bytes16(0)));

        require(validators[merklizedPubkey].status == VALIDATOR_STATUS.INACTIVE, "EigenPod.verifyCorrectWithdrawalCredentials: Validator not inactive");
        // verify validator proof
        BeaconChainProofs.verifyValidatorFields(
            beaconStateRoot,
            proofs,
            validatorFields
        );
        // require that the first field is the merkleized pubkey
        require(validatorFields[0] == merklizedPubkey, "EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for provided pubkey");

        require(validatorFields[1] == podWithdrawalCredentials().toBytes32(0), "EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for this EigenPod");
        // convert the balance field from 8 bytes of little endian to uint64 big endian 💪
        uint64 validatorBalance = Endian.fromLittleEndianUint64(validatorFields[2]);
        // make sure the balance is greater than the amount restaked per validator
        require(validatorBalance >= REQUIRED_BALANCE_GWEI, "EigenPod.verifyCorrectWithdrawalCredentials: validator's balance must be greater than or equal to restaked balance per operator");
        // set the status to active
        validators[merklizedPubkey].status = VALIDATOR_STATUS.ACTIVE;
        // set the effective balance to REQUIRED_BALANCE
        validators[merklizedPubkey].effectiveBalance = REQUIRED_BALANCE_GWEI;
        // deposit RESTAKED_BALANCE_PER_VALIDATOR for new validator
        // @dev balances are in GWEI so need to convert
        investmentManager.depositBeaconChainETH(podOwner, REQUIRED_BALANCE_WEI);
    }

    /**
     * @notice This function records an overcommitment of stake to EigenLayer on behalf of a certain validator.
     *         If successful, the overcommitted are slashed (available for withdrawal whenever the pod's balance allows).
     *         They are also removed from the InvestmentManager and undelegated.
     * @param pubkey is the BLS public key for the validator.
     * @param proofs is the bytes that prove the validator's metadata against a beacon state root
     * @param validatorFields are the fields of the "Validator Container", refer to consensus specs 
     * @param beaconChainETHStrategyIndex is the index of the beaconChainETHStrategy for the pod owner for the callback to 
     *                                    the InvestmentManger in case it must be removed
     * for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
     */
    function verifyBalanceUpdate(
        bytes calldata pubkey, 
        bytes calldata proofs, 
        bytes32[] calldata validatorFields,
        uint256 beaconChainETHStrategyIndex
    ) external {
        //TODO: tailor this to production oracle
        bytes32 beaconStateRoot = eigenPodManager.getBeaconChainStateRoot();
        // get merklizedPubkey
        bytes32 merklizedPubkey = sha256(abi.encodePacked(pubkey, bytes16(0)));
        require(validators[merklizedPubkey].status == VALIDATOR_STATUS.ACTIVE, "EigenPod.verifyBalanceUpdate: Validator not active");
        // verify validator proof
        BeaconChainProofs.verifyValidatorFields(
            beaconStateRoot,
            proofs,
            validatorFields
        );
        // require that the first field is the merkleized pubkey
        require(validatorFields[0] == merklizedPubkey, "EigenPod.verifyBalanceUpdate: Proof is not for provided pubkey");
        // convert the balance field from 8 bytes of little endian to uint64 big endian 💪
        uint64 validatorBalance = Endian.fromLittleEndianUint64(validatorFields[2]);
        require(validatorBalance != 0, "EigenPod.verifyCorrectWithdrawalCredentials: cannot prove balance update on full withdrawal");
        require(validatorBalance <= REQUIRED_BALANCE_GWEI, "EigenPod.verifyCorrectWithdrawalCredentials: validator's balance must be less than the restaked balance per operator");
        // set the effective balance of the validator to 0 and mark them as overcommitted
        validators[merklizedPubkey].effectiveBalance = 0;
        validators[merklizedPubkey].status = VALIDATOR_STATUS.OVERCOMMITTED;
        // allow EigenLayer to slash the overcommitted balance, which is REQUIRED_BALANCE_WEI
        // @dev if the validator's balance ever falls below REQUIRED_BALANCE_WEI
        slashableBalanceDueToOvercommitting += REQUIRED_BALANCE_WEI;
        // remove and undelegate shares in EigenLayer
        investmentManager.recordOvercommittedBeaconChainETH(podOwner, beaconChainETHStrategyIndex, REQUIRED_BALANCE_WEI);
    }

    /**
     * @notice This function records a full withdrawal on behalf of one of the Ethereum validators for this EigenPod
     * @param pubkey is the BLS public key for the validator.
     * for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
     */
    function verifyBeaconChainFullWithdrawal(
        bytes calldata pubkey, 
        bytes calldata,
        uint256 beaconChainETHStrategyIndex
    ) external {
        //TODO: tailor this to production oracle
        bytes32 beaconStateRoot = eigenPodManager.getBeaconChainStateRoot();
        // get merklizedPubkey
        bytes32 merklizedPubkey = sha256(abi.encodePacked(pubkey, bytes16(0)));
        require(validators[merklizedPubkey].status != VALIDATOR_STATUS.INACTIVE, "EigenPod.verifyBeaconChainFullWithdrawal: Validator is inactive");
        // TODO: verify withdrawal proof 
        uint32 withdrawalBlockNumber = 0;
        uint256 withdrawalAmount = 0; // in WEI!

        require(MAX_PARTIAL_WTIHDRAWAL_AMOUNT_GWEI < withdrawalAmount, "EigenPod.verifyBeaconChainFullWithdrawal: cannot prove a partial withdrawal");

        // set the effective balance of the validator to 0 and mark them as inactive
        validators[merklizedPubkey].effectiveBalance = 0;

        // if the withdrawal amount is greater than the REQUIRED_BALANCE (i.e. the amount restaked on EigenLayer)
        if(withdrawalAmount >= REQUIRED_BALANCE_WEI) {
            // then the excess is immidiately withdrawable
            withdrawableDueToExcess += withdrawalAmount - REQUIRED_BALANCE_WEI;
            // and the extra execution layer ETH in the contract is REQUIRED_BALACE that must be wtihdrawn from EigenLayer
            restakedExecutionLayerETH += REQUIRED_BALANCE_WEI;
        } else {
            // if the validator was overcommitted but the contract did not take note, record the slashing event
            if(validators[merklizedPubkey].status == VALIDATOR_STATUS.ACTIVE) {
                // allow EigenLayer to slash the remaining obligations after this slashing
                slashableBalanceDueToOvercommitting += REQUIRED_BALANCE_WEI - withdrawalAmount;
                // remove and undelegate shares in EigenLayer
                investmentManager.recordOvercommittedBeaconChainETH(podOwner, beaconChainETHStrategyIndex, REQUIRED_BALANCE_WEI);
            }
            // otherwise increment the ETH in execution layer by the withdrawalAmount
            restakedExecutionLayerETH += withdrawalAmount;
        }

        // set the validator status to inactive
        validators[merklizedPubkey].status = VALIDATOR_STATUS.INACTIVE;

        // pay off any new or existing slashing obligations
        payOffSlashingObligations();
    }

    /**
     * @notice Transfers ether balance of this contract to the specified recipient address
     * @notice Called by EigenPodManager to withdrawBeaconChainETH that has been added to its balance due to a withdrawal from the beacon chain.
     * @dev Called during withdrawal or slashing.
     */
    function withdrawBeaconChainETH(
        address recipient,
        uint256 amount
    )
        external
        onlyEigenPodManager
    {
        // increment the amount of eth withdrawn from EigenLayer
        eigenLayerBeaconChainEthWithdrawn += amount;
        // transfer ETH directly from pod to `recipient`
        if (Address.isContract(recipient)) {
            // if the recipient is a contract, then call its `receiveBeaconChainETH` function
            IBeaconChainETHReceiver(recipient).receiveBeaconChainETH{value: amount}();
        } else {
            // if the recipient is an EOA, then do a simple transfer
            payable(recipient).transfer(amount);
        }
    }

    // INTERNAL FUNCTIONS
    
    /**
     * @notice Pays off the slashable balance due to overcommitting with funds coming
     *         1) first, from the execution layer ETH that is restaked in EigenLayer because 
     *            it is the ETH that is actually supposed the be restaked
     *         2) second, from the withdrawableDueToExcess to avoid allowing instant withdrawals
     *            from withdrawableDueToExcess in case the balance of the balance of the contract 
     *            is not enough to cover the entire slashing obligation
     */
    function payOffSlashingObligations() internal {
        uint256 amountToSlash = 0;
        if (slashableBalanceDueToOvercommitting > 0) {
            if(slashableBalanceDueToOvercommitting > restakedExecutionLayerETH) {
                // if all of the restakedExecutionLayerETH is not enough, add restakedExecutionLayerETH to the amountToSlash
                amountToSlash += restakedExecutionLayerETH;
                restakedExecutionLayerETH = 0;
            } else {
                // if restakedExecutionLayerETH is enough, slash all that is necessary
                eigenPodManager.addSlashedBalance{value: slashableBalanceDueToOvercommitting}(podOwner);
                slashableBalanceDueToOvercommitting = 0;
                restakedExecutionLayerETH -= slashableBalanceDueToOvercommitting;
                return;
            }

            if(slashableBalanceDueToOvercommitting > amountToSlash + withdrawableDueToExcess) {
                // if all of the restakedExecutionLayerETH+withdrawableDueToExcess is not enough, send it all
                eigenPodManager.addSlashedBalance{value: amountToSlash + withdrawableDueToExcess}(podOwner);
                slashableBalanceDueToOvercommitting -= amountToSlash + withdrawableDueToExcess;
                withdrawableDueToExcess = 0;
            } else {
                // if restakedExecutionLayerETH+withdrawableDueToExcess is enough, slash all that is necessary
                eigenPodManager.addSlashedBalance{value: slashableBalanceDueToOvercommitting}(podOwner);
                slashableBalanceDueToOvercommitting = 0;
                withdrawableDueToExcess -= amountToSlash + withdrawableDueToExcess - slashableBalanceDueToOvercommitting;
                return;
            }

            // uint256 balance = address(this).balance;
            // if(slashableBalanceDueToOvercommitting > balance) {
            //     // if the entire balance is not enough, send it all
            //     eigenPodManager.addSlashedBalance{value: balance}(podOwner);
            //     slashableBalanceDueToOvercommitting -= balance;
            // } else {
            //     // if the entire balance is enough, slash all that is necessary
            //     eigenPodManager.addSlashedBalance{value: slashableBalanceDueToOvercommitting}(podOwner);
            //     slashableBalanceDueToOvercommitting = 0;
            //     return;
            // }
        }
    }

    function podWithdrawalCredentials() internal view returns(bytes memory) {
        return abi.encodePacked(bytes1(uint8(1)), bytes11(0), address(this));
    }

    function uint256ToCumulativeFullWithdrawal(uint256 value) internal pure returns(uint32, uint64) {
        // uint256 = uint160(0), uint32(blockNumber) uint64(amount)
        return (uint32(value >> 64), uint64(value));
    }

    function cumulativeFullWithdrawalToUint256(uint32 blockNumber, uint64 amount) internal pure returns(uint256) {
        // uint256 = uint160(0), uint32(blockNumber) uint64(amount)
        return (uint256(blockNumber) << 64) | uint256(amount);    
    }
}