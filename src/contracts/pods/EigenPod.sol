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

    /// @notice The amount of eth, in wei, that is added to the penalty balance of the pod in case a validator's beacon chain balance ever falls
    ///         below REQUIRED_BALANCE_GWEI
    /// @dev currently this is set to REQUIRED_BALANCE_GWEI
    uint64 internal immutable OVERCOMMITMENT_PENALTY_AMOUNT_GWEI;

    /// @notice The amount of eth, in wei, that is restaked per validator
    uint256 internal immutable REQUIRED_BALANCE_WEI;

    /// @notice The amount of eth, in gwei, that can be part of a full withdrawal at the minimum
    uint64 internal immutable MIN_FULL_WITHDRAWAL_AMOUNT_GWEI;

    /// @notice The single EigenPodManager for EigenLayer
    IEigenPodManager public eigenPodManager;

    /// @notice The owner of this EigenPod
    address public podOwner;

    /// @notice this is a mapping of validator keys to a Validator struct containing pertinent info about the validator
    mapping(uint64 => VALIDATOR_STATUS) public validatorStatus;

    /// @notice the claims on the amount of deserved partial withdrawals for the validators of an EigenPod
    PartialWithdrawalClaim[] public partialWithdrawalClaims;

    /// @notice the amount of execution layer ETH in this contract that is staked in EigenLayer (i.e. withdrawn from beaconchain but not EigenLayer), 
    uint64 public restakedExecutionLayerGwei;

    /// @notice the excess balance from full withdrawals over RESTAKED_BALANCE_PER_VALIDATOR or partial withdrawals
    uint64 public instantlyWithdrawableBalanceGwei;

    /// @notice the amount of penalties that have been paid from instantlyWithdrawableBalanceGwei or partial withdrawals. These can be rolled
    ///         over from restakedExecutionLayerGwei into instantlyWithdrawableBalanceGwei when all existing penalties have been paid
    uint64 public rollableBalanceGwei;

    /// @notice the total amount of gwei outstanding (i.e. to-be-paid) penalties due to over committing to EigenLayer on behalf of this pod
    uint64 public penaltiesDueToOvercommittingGwei;

    /// @notice Emitted when a validator stakes via an eigenPod
    event EigenPodStaked(bytes pubkey);

    /// @notice Emmitted when a partial withdrawal claim is made on an EigenPod
    event PartialWithdrawalClaimRecorded(uint32 currBlockNumber, uint64 partialWithdrawalAmountGwei);

    /// @notice Emitted when a partial withdrawal claim is successfully redeemed
    event PartialWithdrawalRedeemed(address indexed recipient, uint64 partialWithdrawalAmountGwei);

    /// @notice Emitted when restaked beacon chain ETH is withdrawn from the eigenPod.
    event RestakedBeaconChainETHWithdrawn(address indexed recipient, uint256 amount);

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
        OVERCOMMITMENT_PENALTY_AMOUNT_GWEI = REQUIRED_BALANCE_GWEI;
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
        emit EigenPodStaked(pubkey);
    }

    /**
     * @notice This function verifies that the withdrawal credentials of the podOwner are pointed to
     * this contract.  It verifies the provided proof of the ETH validator against the beacon chain state
     * root, marks the validator as 'active' in EigenLayer, and credits the restaked ETH in Eigenlayer.
     * @param proofs is the bytes that prove the ETH validator's metadata against a beacon state root
     * @param validatorFields are the fields of the "Validator Container", refer to consensus specs 
     * for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
     */
    function verifyCorrectWithdrawalCredentials(
        bytes calldata proofs, 
        bytes32[] calldata validatorFields
    ) external {
        // TODO: tailor this to production oracle
        bytes32 beaconStateRoot = eigenPodManager.getBeaconChainStateRoot();

        // verify ETH validator proof
        uint64 validatorIndex = BeaconChainProofs.verifyValidatorFields(
            beaconStateRoot,
            proofs,
            validatorFields
        );

        require(validatorStatus[validatorIndex] == VALIDATOR_STATUS.INACTIVE, "EigenPod.verifyCorrectWithdrawalCredentials: Validator not inactive");
        require(validatorFields[BeaconChainProofs.VALIDATOR_WITHDRAWAL_CREDENTIALS_INDEX] == podWithdrawalCredentials().toBytes32(0), "EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for this EigenPod");
        // convert the balance field from 8 bytes of little endian to uint64 big endian 💪
        uint64 validatorBalanceGwei = Endian.fromLittleEndianUint64(validatorFields[BeaconChainProofs.VALIDATOR_BALANCE_INDEX]);
        // make sure the balance is greater than the amount restaked per validator
        require(validatorBalanceGwei >= REQUIRED_BALANCE_GWEI, "EigenPod.verifyCorrectWithdrawalCredentials: ETH validator's balance must be greater than or equal to restaked balance per operator");
        // set the status to active
        validatorStatus[validatorIndex] = VALIDATOR_STATUS.ACTIVE;
        // deposit RESTAKED_BALANCE_PER_VALIDATOR for new ETH validator
        // @dev balances are in GWEI so need to convert
        eigenPodManager.restakeBeaconChainETH(podOwner, REQUIRED_BALANCE_WEI);
    }

    /**
     * @notice This function records an overcommitment of stake to EigenLayer on behalf of a certain ETH validator.
     *         If successful, the overcommitted balance is penalized (available for withdrawal whenever the pod's balance allows).
     *         The ETH validator's shares in the enshrined beaconChainETH strategy are also removed from the InvestmentManager and undelegated.
     * @param proofs is the bytes that prove the ETH validator's metadata against a beacon state root
     * @param validatorFields are the fields of the "Validator Container", refer to consensus specs 
     * @param beaconChainETHStrategyIndex is the index of the beaconChainETHStrategy for the pod owner for the callback to 
     *                                    the InvestmentManger in case it must be removed from the list of the podOwners strategies
     * for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
     */
    function verifyOvercommittedStake(
        bytes calldata proofs, 
        bytes32[] calldata validatorFields,
        uint256 beaconChainETHStrategyIndex
    ) external {
        //TODO: tailor this to production oracle
        bytes32 beaconStateRoot = eigenPodManager.getBeaconChainStateRoot();
        // verify ETH validator proof
        uint64 validatorIndex = BeaconChainProofs.verifyValidatorFields(
            beaconStateRoot,
            proofs,
            validatorFields
        );

        require(validatorStatus[validatorIndex] == VALIDATOR_STATUS.ACTIVE, "EigenPod.verifyBalanceUpdate: Validator not active");
        // convert the balance field from 8 bytes of little endian to uint64 big endian 💪
        uint64 validatorBalance = Endian.fromLittleEndianUint64(validatorFields[BeaconChainProofs.VALIDATOR_BALANCE_INDEX]);

        require(validatorBalance != 0, "EigenPod.verifyCorrectWithdrawalCredentials: cannot prove balance update on full withdrawal");
        require(validatorBalance < REQUIRED_BALANCE_GWEI, "EigenPod.verifyCorrectWithdrawalCredentials: validator's balance must be less than the restaked balance per operator");
        // mark the ETH validator as overcommitted
        validatorStatus[validatorIndex] = VALIDATOR_STATUS.OVERCOMMITTED;
        // allow EigenLayer to penalize the overcommitted balance, which is OVERCOMMITMENT_PENALTY_AMOUNT_GWEI
        // @dev if the ETH validator's balance ever falls below REQUIRED_BALANCE_GWEI
        penaltiesDueToOvercommittingGwei += OVERCOMMITMENT_PENALTY_AMOUNT_GWEI;
        // remove and undelegate shares in EigenLayer
        eigenPodManager.recordOvercommittedBeaconChainETH(podOwner, beaconChainETHStrategyIndex, REQUIRED_BALANCE_WEI);
    }

    /**
     * @notice This function records a full withdrawal on behalf of one of the Ethereum validators for this EigenPod
     * @param validatorIndex is the validator index for the ETH validator.
     * @param beaconChainETHStrategyIndex is the index of the beaconChainETHStrategy for the pod owner for the callback to 
     *                                    the EigenPodManager to the InvestmentManager in case it must be removed from the 
     *                                    podOwner's list of strategies
     */
    function verifyBeaconChainFullWithdrawal(
        uint64 validatorIndex, 
        bytes calldata proofs, 
        bytes32[] calldata withdrawalFields,
        uint256 beaconChainETHStrategyIndex
    ) external {
        //TODO: tailor this to production oracle
        bytes32 beaconStateRoot = eigenPodManager.getBeaconChainStateRoot();

        require(validatorStatus[validatorIndex] != VALIDATOR_STATUS.INACTIVE && validatorStatus[validatorIndex] != VALIDATOR_STATUS.WITHDRAWN,
            "EigenPod.verifyBeaconChainFullWithdrawal: ETH validator is inactive on EigenLayer, or full withdrawal has already been proven");

        BeaconChainProofs.verifyWithdrawalProofs(
            beaconStateRoot,
            proofs,
            withdrawalFields
        );


        require(validatorIndex == Endian.fromLittleEndianUint64(withdrawalFields[1]), "provided validatorIndex does not match withdrawal proof");


        uint32 withdrawalBlockNumber = uint32(block.number);
        uint64 withdrawalAmountGwei = Endian.fromLittleEndianUint64(withdrawalFields[3]);

        require(MIN_FULL_WITHDRAWAL_AMOUNT_GWEI <= withdrawalAmountGwei, "EigenPod.verifyBeaconChainFullWithdrawal: withdrawal is too small to be a full withdrawal");

        // if the withdrawal amount is greater than the REQUIRED_BALANCE_GWEI (i.e. the amount restaked on EigenLayer)
        if (withdrawalAmountGwei >= REQUIRED_BALANCE_GWEI) {
            // then the excess is immediately withdrawable
            instantlyWithdrawableBalanceGwei += withdrawalAmountGwei - REQUIRED_BALANCE_GWEI;
            // and the extra execution layer ETH in the contract is REQUIRED_BALANCE_GWEI, which must be withdrawn through EigenLayer's normal withdrawal process
            restakedExecutionLayerGwei += REQUIRED_BALANCE_GWEI;
        } else {
            // if the ETH validator was overcommitted but the contract did not take note, record the penalty
            if (validatorStatus[validatorIndex] == VALIDATOR_STATUS.ACTIVE) {
                /// allow EigenLayer to penalize the overcommitted balance. in this case, the penalty is reduced -- since we know that we actually have the
                /// withdrawal amount backing what is deposited in EigenLayer, we can minimize the negative effect on middlewares by minimizing the penalty
                penaltiesDueToOvercommittingGwei += OVERCOMMITMENT_PENALTY_AMOUNT_GWEI - withdrawalAmountGwei;
                // remove and undelegate shares in EigenLayer
                eigenPodManager.recordOvercommittedBeaconChainETH(podOwner, beaconChainETHStrategyIndex, REQUIRED_BALANCE_WEI);
            }
            // in this case, increment the ETH in execution layer by the withdrawalAmount (since we cannot increment by the full REQUIRED_BALANCE_GWEI)
            restakedExecutionLayerGwei += withdrawalAmountGwei;
        }

        // set the ETH validator status to withdrawn
        validatorStatus[validatorIndex] = VALIDATOR_STATUS.WITHDRAWN;

        // check withdrawal against current claim
        uint256 claimsLength = partialWithdrawalClaims.length;
        if (claimsLength != 0) {
            PartialWithdrawalClaim memory currentClaim = partialWithdrawalClaims[claimsLength - 1];
            /**
             * if a full withdrawal is proven before the current partial withdrawal claim and the partial withdrawal claim 
             * is pending (still in its fraud proof period), then the partial withdrawal claim is incorrect and fraudulent
             */
            if (withdrawalBlockNumber <= currentClaim.creationBlockNumber && currentClaim.status == PARTIAL_WITHDRAWAL_CLAIM_STATUS.PENDING) {
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
     * @param expireBlockNumber this is the block number before which the call to this function must be mined to avoid race conditions with pending withdrawals
     *                          it will be set to the blockNumber at which the next full withdrawal for a validator on this pod is going to occur
     *                          or type(uint32).max otherwise
     * @dev the sender should be able to safely set the value to type(uint32).max if there are no pending full withdrawals
     */
    function recordPartialWithdrawalClaim(uint32 expireBlockNumber) external onlyEigenPodOwner {
        uint32 currBlockNumber = uint32(block.number);
        require(currBlockNumber < expireBlockNumber, "EigenPod.recordBalanceSnapshot: partialWithdrawalClaim mined too late");
        // address(this).balance / GWEI_TO_WEI = restakedExecutionLayerGwei + 
        //                                       instantlyWithdrawableBalanceGwei + 
        //                                       partialWithdrawalsGwei
        uint256 claimsLength = partialWithdrawalClaims.length;
        // we do not allow parallel withdrawal claims to avoid complexity
        require(
            // either no claims have been made yet
            claimsLength == 0 ||
            // or the last claim is not pending
            partialWithdrawalClaims[claimsLength - 1].status != PARTIAL_WITHDRAWAL_CLAIM_STATUS.PENDING,
            "EigenPod.recordPartialWithdrawalClaim: cannot make a new claim until previous claim is not pending"
        );

        uint64 partialWithdrawalAmountGwei = uint64(address(this).balance / GWEI_TO_WEI) - restakedExecutionLayerGwei - instantlyWithdrawableBalanceGwei;
        // push claim to the end of the list
        partialWithdrawalClaims.push(
            PartialWithdrawalClaim({ 
                status: PARTIAL_WITHDRAWAL_CLAIM_STATUS.PENDING, 
                creationBlockNumber: currBlockNumber,
                fraudproofPeriodEndBlockNumber: currBlockNumber + PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS,
                partialWithdrawalAmountGwei: partialWithdrawalAmountGwei
            })
        );

        emit PartialWithdrawalClaimRecorded(currBlockNumber, partialWithdrawalAmountGwei);
    }

    /// @notice This function allows pod owners to redeem their partial withdrawals after the dispute period has passed
    function redeemLatestPartialWithdrawal(address recipient) external onlyEigenPodOwner {
        // load claim into memory, note this function should and will fail if there are no claims yet
        uint256 lastClaimIndex = partialWithdrawalClaims.length - 1;
        PartialWithdrawalClaim memory claim = partialWithdrawalClaims[lastClaimIndex];
        require(
            claim.status == PARTIAL_WITHDRAWAL_CLAIM_STATUS.PENDING,
            "EigenPod.redeemLatestPartialWithdrawal: can only redeem partial withdrawals after fraud proof period"
        );
        // mark the claim's status as redeemed
        partialWithdrawalClaims[lastClaimIndex].status = PARTIAL_WITHDRAWAL_CLAIM_STATUS.REDEEMED;
        require(
            uint32(block.number) > claim.fraudproofPeriodEndBlockNumber,
            "EigenPod.redeemLatestPartialWithdrawal: can only redeem partial withdrawals after fraud proof period"
        );
        // pay penalties if possible
        if (penaltiesDueToOvercommittingGwei > 0) {
            if (penaltiesDueToOvercommittingGwei > claim.partialWithdrawalAmountGwei) {
                // if all of the partial withdrawal is not enough, send it all
                eigenPodManager.payPenalties{value: claim.partialWithdrawalAmountGwei * GWEI_TO_WEI}(podOwner);
                // allow this amount to be rolled over from restakedExecutionLayerGwei to instantlyWithdrawableBalanceGwei
                // if penalties are ever fully paid in the future
                rollableBalanceGwei += claim.partialWithdrawalAmountGwei;
                penaltiesDueToOvercommittingGwei -= claim.partialWithdrawalAmountGwei;
                claim.partialWithdrawalAmountGwei = 0;
            } else {
                // if partial withdrawal is enough, penalize all that is necessary
                eigenPodManager.payPenalties{value: penaltiesDueToOvercommittingGwei * GWEI_TO_WEI}(podOwner);
                // allow this amount to be rolled over from restakedExecutionLayerGwei to instantlyWithdrawableBalanceGwei
                // if penalties are ever fully paid in the future
                rollableBalanceGwei += penaltiesDueToOvercommittingGwei;
                claim.partialWithdrawalAmountGwei -= penaltiesDueToOvercommittingGwei;
                penaltiesDueToOvercommittingGwei = 0;
                return;
            }
        }
        
        Address.sendValue(payable(recipient), claim.partialWithdrawalAmountGwei * GWEI_TO_WEI);

        emit PartialWithdrawalRedeemed(recipient, claim.partialWithdrawalAmountGwei);
    }

    /**
     * @notice Withdraws `amount` gwei to the podOwner from their instantlyWithdrawableBalanceGwei
     * @param amountGwei is the amount, in gwei, to withdraw
     */
    function withdrawInstantlyWithdrawableBalanceGwei(uint64 amountGwei) external {
        require(instantlyWithdrawableBalanceGwei >= amountGwei, "EigenPod.withdrawInstantlyWithdrawableBalanceGwei: not enough instantlyWithdrawableBalanceGwei to withdraw");
        instantlyWithdrawableBalanceGwei -= amountGwei;
        // send amountGwei to podOwner
        Address.sendValue(payable(podOwner), amountGwei * GWEI_TO_WEI);
    }

    /**
     * @notice Rebalances restakedExecutionLayerGwei in case penalties were previously paid from instantlyWithdrawableBalanceGwei or partial 
     *         withdrawal, so the EigenPod thinks podOwner has more restakedExecutionLayerGwei and staked balance than beaconChainETH on EigenLayer
     * @param amountGwei is the amount, in gwei, to roll over
     */
    function rollOverRollableBalance(uint64 amountGwei) external {
        require(restakedExecutionLayerGwei >= amountGwei, "EigenPod.rollOverRollableBalance: not enough restakedExecutionLayerGwei to roll over");
        // remove rollableBalanceGwei from restakedExecutionLayerGwei and add it to instantlyWithdrawableBalanceGwei
        restakedExecutionLayerGwei -= amountGwei;
        instantlyWithdrawableBalanceGwei += amountGwei;
        // mark amountGwei as having been rolled over
        rollableBalanceGwei -= amountGwei;
        // pay penalties as much as possible to avoid podOwner from instantly withdrawing with existing penalties
        _payOffPenalties();
    }

    /**
     * @notice Transfers ether balance of this contract to the specified recipient address
     * @notice Called by EigenPodManager to withdrawBeaconChainETH that has been added to its balance due to a withdrawal from the beacon chain.
     * @dev Called during withdrawal or slashing.
     */
    function withdrawRestakedBeaconChainETH(
        address recipient,
        uint256 amountWei
    )
        external
        onlyEigenPodManager
    {

        // reduce the restakedExecutionLayerGwei
        restakedExecutionLayerGwei -= uint64(amountWei / GWEI_TO_WEI);
        
        // transfer ETH directly from pod to `recipient`
        Address.sendValue(payable(recipient), amountWei);

        emit RestakedBeaconChainETHWithdrawn(recipient, amountWei);
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
        uint64 penaltiesDueToOvercommittingGweiMemory = penaltiesDueToOvercommittingGwei;
        if (penaltiesDueToOvercommittingGweiMemory != 0) {
            uint64 amountToPenalizeGwei = 0;
            if (penaltiesDueToOvercommittingGweiMemory > restakedExecutionLayerGwei) {
                // if all of the restakedExecutionLayerGwei is not enough, add restakedExecutionLayerGwei to the amountToPenalizeGwei
                amountToPenalizeGwei += restakedExecutionLayerGwei;
                restakedExecutionLayerGwei = 0;
            } else {
                // if restakedExecutionLayerETH is enough, penalize all that is necessary
                eigenPodManager.payPenalties{value: penaltiesDueToOvercommittingGweiMemory * GWEI_TO_WEI}(podOwner);
                restakedExecutionLayerGwei -= penaltiesDueToOvercommittingGweiMemory;
                penaltiesDueToOvercommittingGwei = 0;
                return;
            }

            // Set `amountToPenalizeGwei` to the max that can be penalized using instantly withdrawable funds
            uint64 instantlyWithdrawableBalanceGweiMemory = instantlyWithdrawableBalanceGwei;
            amountToPenalizeGwei += instantlyWithdrawableBalanceGweiMemory;

            if (penaltiesDueToOvercommittingGweiMemory > amountToPenalizeGwei) {
                // if all of the restakedExecutionLayerETH+instantlyWithdrawableBalanceGwei is not enough, send it all
                eigenPodManager.payPenalties{value: amountToPenalizeGwei * GWEI_TO_WEI}(podOwner);
                // allow this amount to be rolled over from restakedExecutionLayerGwei to instantlyWithdrawableBalanceGwei
                // if penalties are ever fully paid in the future
                rollableBalanceGwei += instantlyWithdrawableBalanceGweiMemory;
                instantlyWithdrawableBalanceGwei = 0;
                penaltiesDueToOvercommittingGwei -= amountToPenalizeGwei;
            } else {
                // if restakedExecutionLayerETH+instantlyWithdrawableBalanceGwei is enough, penalize all that is necessary
                eigenPodManager.payPenalties{value: penaltiesDueToOvercommittingGweiMemory * GWEI_TO_WEI}(podOwner);
                uint64 leftoverExcessGwei = amountToPenalizeGwei - penaltiesDueToOvercommittingGweiMemory;
                // allow this amount to be rolled over from restakedExecutionLayerGwei to instantlyWithdrawableBalanceGwei
                // if penalties are ever fully paid in the future
                rollableBalanceGwei += instantlyWithdrawableBalanceGweiMemory - leftoverExcessGwei;
                instantlyWithdrawableBalanceGwei = leftoverExcessGwei;
                penaltiesDueToOvercommittingGwei = 0;
                return;
            }
        }
    }

    function podWithdrawalCredentials() internal view returns(bytes memory) {
        return abi.encodePacked(bytes1(uint8(1)), bytes11(0), address(this));
    }

}