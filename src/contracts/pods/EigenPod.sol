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
 * - creating new ETH validators with their withdrawal credentials pointed to this contract
 * - proving from beacon chain state roots that withdrawal credentials are pointed to this contract
 * - proving from beacon chain state roots the balances of ETH validators with their withdrawal credentials
 *   pointed to this contract
 * - updating aggregate balances in the EigenPodManager
 * - withdrawing eth when withdrawals are initiated
 * @dev Note that all beacon chain balances are stored as gwei within the beacon chain datastructures. We choose
 *   to account balances and penalties in terms of gwei in the EigenPod contract and convert to wei when making
 *   calls to other contracts
 */
contract EigenPod is IEigenPod, Initializable, Test {
    using BytesLib for bytes;

    uint64 internal constant GWEI_TO_WEI = 1e9;

    //TODO: change this to constant in prod
    /// @notice This is the beacon chain deposit contract
    IETHPOSDeposit internal immutable ethPOS;

    /// @notice The length, in blocks, if the fraud proof period following a claim on the amount of partial withdrawals in an EigenPod
    uint32 immutable public PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS;

    /// @notice The amount of eth, in gwei, that is restaked per validator
    uint64 internal immutable REQUIRED_BALANCE_GWEI;

    /// @notice The amount of eth, in wei, that is restaked per validator
    uint256 internal immutable REQUIRED_BALANCE_WEI;

    /// @notice The amount of eth, in gwei, that can be part of a full withdrawal at the minimum
    uint64 internal immutable MIN_FULL_WITHDRAWAL_AMOUNT_GWEI;

    /// @notice The single EigenPodManager for EigenLayer
    IEigenPodManager public eigenPodManager;

    /// @notice The owner of this EigenPod
    address public podOwner;

    /// @notice this is a mapping of validator keys to a Validator struct containing pertinent info about the validator
    mapping(bytes32 => VALIDATOR_STATUS) public validatorStatus;

    /// @notice the claims on the amount of deserved partial withdrawals for the validators of an EigenPod
    PartialWithdrawalClaim[] public partialWithdrawalClaims;

    /// @notice the amount of execution layer ETH in this contract that is staked in EigenLayer (i.e. withdrawn from beaconchain but not EigenLayer), 
    uint64 public restakedExecutionLayerGwei;

    /// @notice the excess balance from full withdrawals over RESTAKED_BALANCE_PER_VALIDATOR or partial withdrawals
    uint64 public instantlyWithdrawableBalanceGwei;

    /// @notice the total amount of gwei penalties due to over committing to EigenLayer on behalf of this pod
    uint64 public penaltiesDueToOvercommittingGwei;

    modifier onlyEigenPodManager {
        require(msg.sender == address(eigenPodManager), "EigenPod.onlyEigenPodManager: not eigenPodManager");
        _;
    }

    modifier onlyEigenPodOwner {
        require(msg.sender == podOwner, "EigenPod.onlyEigenPodManager: not podOwner");
        _;
    }

    constructor(IETHPOSDeposit _ethPOS, uint32 _PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS, uint256 _REQUIRED_BALANCE_WEI, uint64 _MIN_FULL_WITHDRAWAL_AMOUNT_GWEI) {
        ethPOS = _ethPOS;
        PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS = _PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS;
        REQUIRED_BALANCE_WEI = _REQUIRED_BALANCE_WEI;
        REQUIRED_BALANCE_GWEI = uint64(_REQUIRED_BALANCE_WEI / GWEI_TO_WEI);
        require(_REQUIRED_BALANCE_WEI % GWEI_TO_WEI == 0, "EigenPod.contructor: _REQUIRED_BALANCE_WEI is not a whole number of gwei");
        MIN_FULL_WITHDRAWAL_AMOUNT_GWEI = _MIN_FULL_WITHDRAWAL_AMOUNT_GWEI;
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
     * this contract.  It verifies the provided proof of the ETH validator against the beacon chain state
     * root.
     * @param pubkey is the BLS public key for the ETH validator.
     * @param proofs is the bytes that prove the ETH validator's metadata against a beacon state root
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

        require(validatorStatus[merklizedPubkey] == VALIDATOR_STATUS.INACTIVE, "EigenPod.verifyCorrectWithdrawalCredentials: Validator not inactive");
        // verify ETH validator proof
        BeaconChainProofs.verifyValidatorFields(
            beaconStateRoot,
            proofs,
            validatorFields
        );
        // require that the first field is the merkleized pubkey
        require(validatorFields[0] == merklizedPubkey, "EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for provided pubkey");

        require(validatorFields[1] == podWithdrawalCredentials().toBytes32(0), "EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for this EigenPod");
        // convert the balance field from 8 bytes of little endian to uint64 big endian 💪
        uint64 validatorBalanceGwei = Endian.fromLittleEndianUint64(validatorFields[2]);

        // make sure the balance is greater than the amount restaked per validator
        require(validatorBalanceGwei >= REQUIRED_BALANCE_GWEI, "EigenPod.verifyCorrectWithdrawalCredentials: ETH validator's balance must be greater than or equal to restaked balance per operator");
        // set the status to active
        validatorStatus[merklizedPubkey] = VALIDATOR_STATUS.ACTIVE;
        // deposit RESTAKED_BALANCE_PER_VALIDATOR for new ETH validator
        // @dev balances are in GWEI so need to convert
        eigenPodManager.restakeBeaconChainETH(podOwner, REQUIRED_BALANCE_WEI);
    }

    /**
     * @notice This function records an overcommitment of stake to EigenLayer on behalf of a certain ETH validator.
     *         If successful, the overcommitted balance is penalized (available for withdrawal whenever the pod's balance allows).
     *         They are also removed from the InvestmentManager and undelegated.
     * @param pubkey is the BLS public key for the ETH validator.
     * @param proofs is the bytes that prove the ETH validator's metadata against a beacon state root
     * @param validatorFields are the fields of the "Validator Container", refer to consensus specs 
     * @param beaconChainETHStrategyIndex is the index of the beaconChainETHStrategy for the pod owner for the callback to 
     *                                    the InvestmentManger in case it must be removed from the list of the podOwners strategies
     * for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
     */
    function verifyOvercommitedStake(
        bytes calldata pubkey, 
        bytes calldata proofs, 
        bytes32[] calldata validatorFields,
        uint256 beaconChainETHStrategyIndex
    ) external {
        //TODO: tailor this to production oracle
        bytes32 beaconStateRoot = eigenPodManager.getBeaconChainStateRoot();
        // get merklizedPubkey
        bytes32 merklizedPubkey = sha256(abi.encodePacked(pubkey, bytes16(0)));
        require(validatorStatus[merklizedPubkey] == VALIDATOR_STATUS.ACTIVE, "EigenPod.verifyBalanceUpdate: Validator not active");
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
        // mark the ETH validator as overcommitted
        validatorStatus[merklizedPubkey] = VALIDATOR_STATUS.OVERCOMMITTED;
        // allow EigenLayer to penalize the overcommitted balance, which is REQUIRED_BALANCE_GWEI
        // @dev if the ETH validator's balance ever falls below REQUIRED_BALANCE_GWEI
        penaltiesDueToOvercommittingGwei += REQUIRED_BALANCE_GWEI;
        // remove and undelegate shares in EigenLayer
        eigenPodManager.recordOvercommittedBeaconChainETH(podOwner, beaconChainETHStrategyIndex, REQUIRED_BALANCE_WEI);
    }

    /**
     * @notice This function records a full withdrawal on behalf of one of the Ethereum validators for this EigenPod
     * @param pubkey is the BLS public key for the ETH validator.
     * @param beaconChainETHStrategyIndex is the index of the beaconChainETHStrategy for the pod owner for the callback to 
     *                                    the EigenPodManager to the InvestmentManager in case it must be removed from the 
     *                                    podOwner's list of strategies
     */
    function verifyBeaconChainFullWithdrawal(
        bytes calldata pubkey, 
         bytes calldata proofs, 
        bytes32[] calldata validatorFields,
        uint256 beaconChainETHStrategyIndex
    ) external {
        //TODO: tailor this to production oracle
        bytes32 beaconStateRoot = eigenPodManager.getBeaconChainStateRoot();
        // get merklizedPubkey
        bytes32 merklizedPubkey = sha256(abi.encodePacked(pubkey, bytes16(0)));
        require(validatorStatus[merklizedPubkey] != VALIDATOR_STATUS.INACTIVE, "EigenPod.verifyBeaconChainFullWithdrawal: ETH validator is inactive on EigenLayer");
        // TODO: verify withdrawal proof 
        uint32 withdrawalBlockNumber = 0;
        uint64 withdrawalAmountGwei = 0;
        require(MIN_FULL_WITHDRAWAL_AMOUNT_GWEI < withdrawalAmountGwei, "EigenPod.verifyBeaconChainFullWithdrawal: withdrawal is too small to be a full withdrawal");

        // if the withdrawal amount is greater than the REQUIRED_BALANCE (i.e. the amount restaked on EigenLayer)
        if(withdrawalAmountGwei >= REQUIRED_BALANCE_GWEI) {
            // then the excess is immidiately withdrawable
            instantlyWithdrawableBalanceGwei += withdrawalAmountGwei - REQUIRED_BALANCE_GWEI;
            // and the extra execution layer ETH in the contract is REQUIRED_BALACE that must be wtihdrawn from EigenLayer
            restakedExecutionLayerGwei += REQUIRED_BALANCE_GWEI;
        } else {
            // if the ETH validator was overcommitted but the contract did not take note, record the penalty
            if(validatorStatus[merklizedPubkey] == VALIDATOR_STATUS.ACTIVE) {
                // allow EigenLayer to penalize the overcommitted balance
                penaltiesDueToOvercommittingGwei += REQUIRED_BALANCE_GWEI - withdrawalAmountGwei;
                // remove and undelegate shares in EigenLayer
                eigenPodManager.recordOvercommittedBeaconChainETH(podOwner, beaconChainETHStrategyIndex, REQUIRED_BALANCE_WEI);
            }
            // otherwise increment the ETH in execution layer by the withdrawalAmount
            restakedExecutionLayerGwei += withdrawalAmountGwei;
        }

        // set the ETH validator status to inactive
        validatorStatus[merklizedPubkey] = VALIDATOR_STATUS.INACTIVE;

        // check withdrawal against current claim
        uint256 claimsLength = partialWithdrawalClaims.length - 1;
        if(claimsLength != 0) {
            PartialWithdrawalClaim memory currentClaim = partialWithdrawalClaims[partialWithdrawalClaims.length - 1];
            // if a full withdrawal is proven before the current partial withdrawal claim and the partial withdrawal claim 
            // is pending (still in its fraud proof period), then the claim is incorrect and fraudulent
            if(withdrawalBlockNumber <= currentClaim.blockNumber && currentClaim.status == PARTIAL_WITHDRAWAL_CLAIM_STATUS.PENDING) {
                // mark the partial withdrawal claim as failed
                partialWithdrawalClaims[claimsLength - 1].status = PARTIAL_WITHDRAWAL_CLAIM_STATUS.FAILED;
                // TODO: reward the updater
            }
        }

        // pay off any new or existing penalties
        _payOffPenalties();
    }

    /**
     * @notice This function records a balance snapshot for the EigenPod. Its main functionality is to begin an optimistic
     *         claim process on the partial withdrawable balance for the EigenPod owner. The owner is claiming that they have 
     *         proven all full withdrawals until block.number, allowing their partial withdrawal balance to be easily calculated 
     *         via  
     *              address(this).balance / GWEI_TO_WEI = 
     *                  restakedExecutionLayerGwei + 
     *                  instantlyWithdrawableBalanceGwei + 
     *                  partialWithdrawalsGwei
     *         if any other full withdrawals are proven to have happened before block.number, the partial withdrawal is marked as failed
     * @param expireBlockNumber this is the block number before which a balance update to this pod must be mined, in order to avoid race conditions with pending withdrawals.
     *                          The value of this parameter is set by the EigenPodManager. If applicable, it will be set to the blockNumber at which the next full withdrawal for a validator on this pod is going to occur,
     *                          or type(uint32).max otherwise
     */
    function recordPartialWithdrawalClaim(uint32 expireBlockNumber) external onlyEigenPodOwner {
        uint32 currBlockNumber = uint32(block.number);
        require(currBlockNumber < expireBlockNumber, "EigenPod.recordBalanceSnapshot: snapshot mined too late");
        // address(this).balance / GWEI_TO_WEI = restakedExecutionLayerGwei + 
        //                                       instantlyWithdrawableBalanceGwei + 
        //                                       partialWithdrawalsGwei
        uint256 claimsLength = partialWithdrawalClaims.length;
        // we do not allow parallel withdrawal claims to avoid complexity
        require(
            claimsLength == 0 || // either no claims have been made yet
            partialWithdrawalClaims[claimsLength - 1].status != PARTIAL_WITHDRAWAL_CLAIM_STATUS.PENDING, // or the last claim is not pending
            "EigenPod.recordPartialWithdrawalClaim: cannot make a new claim until previous claim is not pending"
        );
        // push claim to the end of the list
        partialWithdrawalClaims.push(
            PartialWithdrawalClaim({ 
                status: PARTIAL_WITHDRAWAL_CLAIM_STATUS.PENDING, 
                blockNumber: currBlockNumber,
                partialWithdrawalAmountGwei: uint64(address(this).balance / GWEI_TO_WEI) - restakedExecutionLayerGwei - instantlyWithdrawableBalanceGwei
            })
        );
    }

    /// @notice This function allows pod owners to redeem their partial withdrawals after the dispute period has passed
    function redeemPartialWithdrawals(address recipient) external onlyEigenPodOwner {
        // load claim into memory, note this function should and will fail if there are no claims yet
        PartialWithdrawalClaim memory claim = partialWithdrawalClaims[partialWithdrawalClaims.length - 1];
        require(
            claim.status == PARTIAL_WITHDRAWAL_CLAIM_STATUS.PENDING,
            "EigenPod.redeemPartialWithdrawals: can only redeem parital withdrawals after fraud proof period"
        );
        // mark the claim's status as redeemed
        claim.status = PARTIAL_WITHDRAWAL_CLAIM_STATUS.REDEEMED;
        require(
            uint32(block.number) - claim.blockNumber > PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS,
            "EigenPod.redeemPartialWithdrawals: can only redeem parital withdrawals after fraud proof period"
        );
        // pay penalties if possible
        if (penaltiesDueToOvercommittingGwei > 0) {
            if(penaltiesDueToOvercommittingGwei > claim.partialWithdrawalAmountGwei) {
                // if all of the parital withdrawal is not enough, send it all
                eigenPodManager.payPenalties{value: claim.partialWithdrawalAmountGwei * GWEI_TO_WEI}(podOwner);
                penaltiesDueToOvercommittingGwei -= claim.partialWithdrawalAmountGwei;
                claim.partialWithdrawalAmountGwei = 0;
            } else {
                // if parital withdrawal is enough, penalize all that is necessary
                eigenPodManager.payPenalties{value: penaltiesDueToOvercommittingGwei * GWEI_TO_WEI}(podOwner);
                penaltiesDueToOvercommittingGwei = 0;
                claim.partialWithdrawalAmountGwei -= penaltiesDueToOvercommittingGwei;
                return;
            }
        }
        // finally, transfer ETH directly from pod to `recipient`
        if (Address.isContract(recipient)) {
            // if the recipient is a contract, then call its `receiveBeaconChainETH` function
            IBeaconChainETHReceiver(recipient).receiveBeaconChainETH{value: claim.partialWithdrawalAmountGwei * GWEI_TO_WEI}();
        } else {
            // if the recipient is an EOA, then do a simple transfer
            payable(recipient).transfer(claim.partialWithdrawalAmountGwei * GWEI_TO_WEI);
        }
    }

    /**
     * @notice Transfers ether balance of this contract to the specified recipient address
     * @notice Called by EigenPodManager to withdrawBeaconChainETH that has been added to its balance due to a withdrawal from the beacon chain.
     * @dev Called during withdrawal or slashing.
     */
    function withdrawRestakedBeaconChainETH(
        address recipient,
        uint256 amount
    )
        external
        onlyEigenPodManager
    {
        emit log_uint(restakedExecutionLayerGwei);
        // reduce the restakedExecutionLayerGwei
        restakedExecutionLayerGwei -= uint64(amount / GWEI_TO_WEI);
        emit log_named_uint("ssssamount", address(this).balance);
        
        // transfer ETH directly from pod to `recipient`
        if (Address.isContract(recipient)) {
            // if the recipient is a contract, then call its `receiveBeaconChainETH` function
            emit log_named_uint("amsssount", address(this).balance);
            IBeaconChainETHReceiver(recipient).receiveBeaconChainETH{value: amount}();
        } else {
            // if the recipient is an EOA, then do a simple transfer
            payable(recipient).transfer(amount);
        }
    }

    // INTERNAL FUNCTIONS
    /**
     * @notice Pays off the penalties due to overcommitting with funds coming
     *         1) first, from the execution layer ETH that is restaked in EigenLayer because 
     *            it is the ETH that is actually supposed the be restaked
     *         2) second, from the instantlyWithdrawableBalanceGwei to avoid allowing instant withdrawals
     *            from instantlyWithdrawableBalanceGwei in case the balance of the contract is not enough 
     *            to cover the entire penalty
     */
    function _payOffPenalties() internal {
        uint64 amountToPenalize = 0;
        if (penaltiesDueToOvercommittingGwei > 0) {
            if(penaltiesDueToOvercommittingGwei > restakedExecutionLayerGwei) {
                // if all of the restakedExecutionLayerGwei is not enough, add restakedExecutionLayerGwei to the amountToPenalize
                amountToPenalize += restakedExecutionLayerGwei;
                restakedExecutionLayerGwei = 0;
            } else {
                // if restakedExecutionLayerETH is enough, penalize all that is necessary
                eigenPodManager.payPenalties{value: penaltiesDueToOvercommittingGwei * GWEI_TO_WEI}(podOwner);
                penaltiesDueToOvercommittingGwei = 0;
                restakedExecutionLayerGwei -= penaltiesDueToOvercommittingGwei;
                return;
            }

            // Set `amountToPenalize` to the max that can be penalized using instantly withdrawable funds
            amountToPenalize += instantlyWithdrawableBalanceGwei;

            if(penaltiesDueToOvercommittingGwei > amountToPenalize) {
                // if all of the restakedExecutionLayerETH+instantlyWithdrawableBalanceGwei is not enough, send it all
                eigenPodManager.payPenalties{value: amountToPenalize * GWEI_TO_WEI}(podOwner);
                penaltiesDueToOvercommittingGwei -= amountToPenalize;
                instantlyWithdrawableBalanceGwei = 0;
            } else {
                // if restakedExecutionLayerETH+instantlyWithdrawableBalanceGwei is enough, penalize all that is necessary
                eigenPodManager.payPenalties{value: penaltiesDueToOvercommittingGwei * GWEI_TO_WEI}(podOwner);
                penaltiesDueToOvercommittingGwei = 0;
                instantlyWithdrawableBalanceGwei -= amountToPenalize - penaltiesDueToOvercommittingGwei;
                return;
            }
        }
    }

    function podWithdrawalCredentials() internal view returns(bytes memory) {
        return abi.encodePacked(bytes1(uint8(1)), bytes11(0), address(this));
    }
}