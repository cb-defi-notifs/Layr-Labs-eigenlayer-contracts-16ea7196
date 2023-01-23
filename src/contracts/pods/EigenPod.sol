// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../libraries/BeaconChainProofs.sol";
import "../libraries/BytesLib.sol";
import "../libraries/Endian.sol";
import "../interfaces/IETHPOSDeposit.sol";
import "../interfaces/IEigenPodManager.sol";
import "../interfaces/IEigenPod.sol";

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
contract EigenPod is IEigenPod, Initializable, ReentrancyGuard {
    using BytesLib for bytes;

    uint256 internal constant GWEI_TO_WEI = 1e9;

    //TODO: change this to constant in prod
    /// @notice This is the beacon chain deposit contract
    IETHPOSDeposit internal immutable ethPOS;

    /// @notice The length, in blocks, of the fraudproof period following a claim on the amount of partial withdrawals in an EigenPod
    uint32 immutable public PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS;

    /// @notice The amount of eth, in gwei, that is restaked per validator
    uint64 public immutable REQUIRED_BALANCE_GWEI;

    /// @notice The amount of eth, in wei, that is added to the penalty balance of the pod in case a validator's beacon chain balance is ever proven to have
    ///         fallen below REQUIRED_BALANCE_GWEI
    /// @dev currently this is set to REQUIRED_BALANCE_GWEI, and we implicitly assume equivalence (esp. in `verifyBeaconChainFullWithdrawal`)
    uint64 public immutable OVERCOMMITMENT_PENALTY_AMOUNT_GWEI;

    /// @notice The amount of eth, in wei, that is restaked per ETH validator into EigenLayer
    uint256 public immutable REQUIRED_BALANCE_WEI;

    /// @notice The minimum amount of eth, in gwei, that can be part of a full withdrawal
    uint64 public immutable MIN_FULL_WITHDRAWAL_AMOUNT_GWEI;

    /// @notice The single EigenPodManager for EigenLayer
    IEigenPodManager public eigenPodManager;

    /// @notice The owner of this EigenPod
    address public podOwner;

    /// @notice this is a mapping of validator indices to a Validator struct containing pertinent info about the validator
    mapping(uint40 => VALIDATOR_STATUS) public validatorStatus;

    /// @notice the claims on the amount of deserved partial withdrawals for the ETH validators of this EigenPod
    /// @dev this array is marked as internal because of how Solidity handles structs in storage -- use the `getPartialWithdrawalClaim` getter function to fetch on this array!
    PartialWithdrawalClaim[] internal partialWithdrawalClaims;

    /// @notice the amount of execution layer ETH in this contract that is staked in EigenLayer (i.e. withdrawn from the Beacon Chain but not from EigenLayer), 
    uint64 public restakedExecutionLayerGwei;

    /// @notice the excess balance from full withdrawals over RESTAKED_BALANCE_PER_VALIDATOR or partial withdrawals
    uint64 public instantlyWithdrawableBalanceGwei;

    /// @notice the amount of penalties that have been paid from instantlyWithdrawableBalanceGwei or from partial withdrawals.
    /// @dev These can be rolled over from restakedExecutionLayerGwei into instantlyWithdrawableBalanceGwei when all existing penalties have been paid        
    uint64 public rollableBalanceGwei;

    /// @notice the total amount of gwei in outstanding (i.e. to-be-paid) penalties due to over-committing to EigenLayer on behalf of this pod
    uint64 public penaltiesDueToOvercommittingGwei;

    /// @notice Emitted when an ETH validator stakes via this eigenPod
    event EigenPodStaked(bytes pubkey);

    /// @notice Emmitted when a partial withdrawal claim is made on the EigenPod
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
        require(msg.sender == podOwner, "EigenPod.onlyEigenPodOwner: not podOwner");
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

    /// @notice Called by EigenPodManager when the owner wants to create another ETH validator.
    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable onlyEigenPodManager {
        // stake on ethpos
        require(msg.value == 32 ether, "EigenPod.stake: must initially stake for any validator with 32 ether");
        ethPOS.deposit{value : 32 ether}(pubkey, _podWithdrawalCredentials(), signature, depositDataRoot);
        emit EigenPodStaked(pubkey);
    }

    /**
     * @notice This function verifies that the withdrawal credentials of the podOwner are pointed to
     * this contract. It verifies the provided proof of the ETH validator against the beacon chain state
     * root, marks the validator as 'active' in EigenLayer, and credits the restaked ETH in Eigenlayer.
     * @param proof is the bytes that prove the ETH validator's metadata against a beacon chain state root
     * @param validatorFields are the fields of the "Validator Container", refer to consensus specs 
     * for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
     */
    function verifyCorrectWithdrawalCredentials(
        uint40 validatorIndex,
        bytes calldata proof, 
        bytes32[] calldata validatorFields
    ) external {
        // TODO: tailor this to production oracle
        bytes32 beaconStateRoot = eigenPodManager.getBeaconChainStateRoot();

        // verify ETH validator proof
        BeaconChainProofs.verifyValidatorFields(
            validatorIndex,
            beaconStateRoot,
            proof,
            validatorFields
        );

        require(validatorStatus[validatorIndex] == VALIDATOR_STATUS.INACTIVE, "EigenPod.verifyCorrectWithdrawalCredentials: Validator not inactive");
        require(validatorFields[BeaconChainProofs.VALIDATOR_WITHDRAWAL_CREDENTIALS_INDEX] == _podWithdrawalCredentials().toBytes32(0),
            "EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for this EigenPod");
        // convert the balance field from 8 bytes of little endian to uint64 big endian 💪
        uint64 validatorBalanceGwei = Endian.fromLittleEndianUint64(validatorFields[BeaconChainProofs.VALIDATOR_BALANCE_INDEX]);
        // make sure the balance is greater than the amount restaked per validator
        require(validatorBalanceGwei >= REQUIRED_BALANCE_GWEI,
            "EigenPod.verifyCorrectWithdrawalCredentials: ETH validator's balance must be greater than or equal to the restaked balance per validator");
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
     * @param proof is the bytes that prove the ETH validator's metadata against a beacon state root
     * @param validatorFields are the fields of the "Validator Container", refer to consensus specs 
     * @param beaconChainETHStrategyIndex is the index of the beaconChainETHStrategy for the pod owner for the callback to 
     *                                    the InvestmentManger in case it must be removed from the list of the podOwners strategies
     * @dev For more details on the Beacon Chain spec, see: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
     */
    function verifyOvercommittedStake(
        uint40 validatorIndex,
        bytes calldata proof, 
        bytes32[] calldata validatorFields,
        uint256 beaconChainETHStrategyIndex
    ) external {
        //TODO: tailor this to production oracle
        bytes32 beaconStateRoot = eigenPodManager.getBeaconChainStateRoot();
        // verify ETH validator proof
        BeaconChainProofs.verifyValidatorFields(
            validatorIndex,
            beaconStateRoot,
            proof,
            validatorFields
        );

        require(validatorStatus[validatorIndex] == VALIDATOR_STATUS.ACTIVE, "EigenPod.verifyBalanceUpdate: Validator not active");
        // convert the balance field from 8 bytes of little endian to uint64 big endian 💪
        uint64 validatorBalance = Endian.fromLittleEndianUint64(validatorFields[BeaconChainProofs.VALIDATOR_BALANCE_INDEX]);

        require(validatorBalance != 0, "EigenPod.verifyCorrectWithdrawalCredentials: cannot prove balance update on full withdrawal");
        require(validatorBalance < REQUIRED_BALANCE_GWEI,
            "EigenPod.verifyCorrectWithdrawalCredentials: validator's balance must be less than the restaked balance per validator");
        // mark the ETH validator as overcommitted
        validatorStatus[validatorIndex] = VALIDATOR_STATUS.OVERCOMMITTED;
        // allow EigenLayer to penalize the overcommitted balance, which is OVERCOMMITMENT_PENALTY_AMOUNT_GWEI
        // @dev if the ETH validator's balance ever falls below REQUIRED_BALANCE_GWEI
        penaltiesDueToOvercommittingGwei += OVERCOMMITMENT_PENALTY_AMOUNT_GWEI;
        // remove and undelegate shares in EigenLayer
        eigenPodManager.recordOvercommittedBeaconChainETH(podOwner, beaconChainETHStrategyIndex, REQUIRED_BALANCE_WEI);
        // pay off any new or existing penalties
        _payOffPenalties();
    }

    /**
     * @notice This function records a full withdrawal on behalf of one of the Ethereum validators for this EigenPod
     * @param proof is the information needed to check the veracity of the block number and withdrawal being proven
     * @param blockNumberRoot is block number at which the withdrawal being proven is claimed to have happened
     * @param withdrawalFields are the fields of the withdrawal being proven
     * @param beaconChainETHStrategyIndex is the index of the beaconChainETHStrategy for the pod owner for the callback to 
     *                                    the EigenPodManager to the InvestmentManager in case it must be removed from the 
     *                                    podOwner's list of strategies
     */
    function verifyBeaconChainFullWithdrawal(
        BeaconChainProofs.WithdrawalAndBlockNumberProof calldata proof,
        bytes32 blockNumberRoot,
        bytes32[] calldata withdrawalFields,
        uint256 beaconChainETHStrategyIndex
    ) external {
        //TODO: tailor this to production oracle
        bytes32 beaconStateRoot = eigenPodManager.getBeaconChainStateRoot();
        // verify the validator filds and block number
        BeaconChainProofs.verifyWithdrawalFieldsAndBlockNumber(
            beaconStateRoot,
            proof,
            blockNumberRoot,
            withdrawalFields
        );
        // get the validator index from 
        uint40 validatorIndex = uint40(Endian.fromLittleEndianUint64(withdrawalFields[BeaconChainProofs.WITHDRAWAL_VALIDATOR_INDEX_INDEX]));
        // make sure that the validator is staked on this pod and is not withdrawn already
        require(validatorStatus[validatorIndex] != VALIDATOR_STATUS.INACTIVE && validatorStatus[validatorIndex] != VALIDATOR_STATUS.WITHDRAWN,
            "EigenPod.verifyBeaconChainFullWithdrawal: ETH validator is inactive on EigenLayer, or full withdrawal has already been proven");

        // parse relevant fields from withdrawal
        uint32 withdrawalBlockNumber = uint32(Endian.fromLittleEndianUint64(blockNumberRoot));
        uint64 withdrawalAmountGwei = Endian.fromLittleEndianUint64(withdrawalFields[BeaconChainProofs.WITHDRAWAL_VALIDATOR_AMOUNT_INDEX]);

        require(MIN_FULL_WITHDRAWAL_AMOUNT_GWEI <= withdrawalAmountGwei, "EigenPod.verifyBeaconChainFullWithdrawal: withdrawal is too small to be a full withdrawal");

        // if the withdrawal amount is greater than the REQUIRED_BALANCE_GWEI (i.e. the amount restaked on EigenLayer, per ETH validator)
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
                // remove and undelegate the amount of overcommitted shares in EigenLayer
                eigenPodManager.recordOvercommittedBeaconChainETH(
                    podOwner,
                    beaconChainETHStrategyIndex,
                    (uint256(REQUIRED_BALANCE_GWEI) - uint256(withdrawalAmountGwei)) * uint256(GWEI_TO_WEI)
                );
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
             * is pending (still in its fraudproof period), then the partial withdrawal claim is incorrect and fraudulent
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
     *         If any other full withdrawals are proven to have happened before block.number, the partial withdrawal is marked as failed
     * @param expireBlockNumber this is the block number before which the call to this function must be mined. To avoid race conditions with pending withdrawals,
     *                          if there are any pending full withrawals to this Eigenpod, this parameter should be set to the blockNumber at which the next full withdrawal
     *                          for a validator on this EigenPod is going to occur.
     * @dev The sender should be able to safely set the value of `expireBlockNumber` to type(uint32).max if there are no pending full withdrawals to this Eigenpod.
     */
    function recordPartialWithdrawalClaim(uint32 expireBlockNumber) external onlyEigenPodOwner {
        uint32 currBlockNumber = uint32(block.number);
        require(currBlockNumber < expireBlockNumber, "EigenPod.recordBalanceSnapshot: recordPartialWithdrawalClaim tx mined too late");
        uint256 claimsLength = partialWithdrawalClaims.length;
        // we do not allow parallel withdrawal claims to minimize complexity
        require(
            // either no claims have been made yet
            claimsLength == 0 ||
            // or the last claim is not pending
            partialWithdrawalClaims[claimsLength - 1].status != PARTIAL_WITHDRAWAL_CLAIM_STATUS.PENDING,
            "EigenPod.recordPartialWithdrawalClaim: cannot make a new claim until previous claim is not pending"
        );

        // address(this).balance / GWEI_TO_WEI = restakedExecutionLayerGwei + 
        //                                       instantlyWithdrawableBalanceGwei + 
        //                                       partialWithdrawalAmountGwei
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

    /// @notice This function allows pod owners to redeem their partial withdrawals after the fraudproof period has elapsed
    function redeemLatestPartialWithdrawal(address recipient) external onlyEigenPodOwner nonReentrant {
        // load claim into memory, note this function should and will fail if there are no claims yet
        uint256 lastClaimIndex = partialWithdrawalClaims.length - 1;        
        PartialWithdrawalClaim memory claim = partialWithdrawalClaims[lastClaimIndex];

        require(
            claim.status == PARTIAL_WITHDRAWAL_CLAIM_STATUS.PENDING,
            "EigenPod.redeemLatestPartialWithdrawal: partial withdrawal either redeemed or failed making it ineligible for redemption"
        );
        require(
            uint32(block.number) > claim.fraudproofPeriodEndBlockNumber,
            "EigenPod.redeemLatestPartialWithdrawal: can only redeem partial withdrawals after fraudproof period"
        );

        // mark the claim's status as redeemed
        partialWithdrawalClaims[lastClaimIndex].status = PARTIAL_WITHDRAWAL_CLAIM_STATUS.REDEEMED;

        // pay penalties if possible
        if (penaltiesDueToOvercommittingGwei != 0) {
            uint64 penaltiesDueToOvercommittingGweiMemory = penaltiesDueToOvercommittingGwei;


            if (penaltiesDueToOvercommittingGweiMemory > claim.partialWithdrawalAmountGwei) {
                // if all of the partial withdrawal is not enough to cover existing penalties, send it all
                eigenPodManager.payPenalties{value: uint256(claim.partialWithdrawalAmountGwei) * uint256(GWEI_TO_WEI)}(podOwner);
                // allow this amount to be rolled over from restakedExecutionLayerGwei to instantlyWithdrawableBalanceGwei if penalties are ever fully paid in the future
                rollableBalanceGwei += claim.partialWithdrawalAmountGwei;
                penaltiesDueToOvercommittingGwei = penaltiesDueToOvercommittingGweiMemory - claim.partialWithdrawalAmountGwei;
                claim.partialWithdrawalAmountGwei = 0;
                return;
            } else {
                // if partial withdrawal is enough, penalize all that is necessary
                eigenPodManager.payPenalties{value: uint256(penaltiesDueToOvercommittingGweiMemory) * uint256(GWEI_TO_WEI)}(podOwner);
                // allow this amount to be rolled over from restakedExecutionLayerGwei to instantlyWithdrawableBalanceGwei if penalties are ever fully paid in the future
                rollableBalanceGwei += penaltiesDueToOvercommittingGweiMemory;
                claim.partialWithdrawalAmountGwei = claim.partialWithdrawalAmountGwei - penaltiesDueToOvercommittingGweiMemory;

                penaltiesDueToOvercommittingGwei = 0;
            }
        }
        // send any remaining ETH (after paying penalties) to the `recipient`
        Address.sendValue(payable(recipient), uint256(claim.partialWithdrawalAmountGwei) * uint256(GWEI_TO_WEI));

        emit PartialWithdrawalRedeemed(recipient, claim.partialWithdrawalAmountGwei);
    }

    /** 
     * @notice Withdraws instantlyWithdrawableBalanceGwei to the specified `recipient`
     * @dev Note that this function is marked as non-reentrant to prevent the recipient calling back into it
     */
    function withdrawInstantlyWithdrawableBalanceGwei(address recipient) external onlyEigenPodOwner nonReentrant {
        uint256 instantlyWithdrawableBalanceGweiMemory = instantlyWithdrawableBalanceGwei;
        instantlyWithdrawableBalanceGwei = 0;
        Address.sendValue(payable(recipient), uint256(instantlyWithdrawableBalanceGweiMemory) * uint256(GWEI_TO_WEI));
    }

    /**
     * @notice Rebalances restakedExecutionLayerGwei in case penalties were previously paid from instantlyWithdrawableBalanceGwei or from partial 
     *         withdrawals, so the EigenPod thinks podOwner has more restakedExecutionLayerGwei and staked balance than their true amount of 'beaconChainETH' on EigenLayer
     * @param amountGwei is the amount, in gwei, to roll over
     */
    function rollOverRollableBalance(uint64 amountGwei) external {
        // this is also checked by built-in underflow checks
        require(restakedExecutionLayerGwei >= amountGwei, "EigenPod.rollOverRollableBalance: not enough restakedExecutionLayerGwei to roll over");
        // remove rollableBalanceGwei from restakedExecutionLayerGwei and add it to instantlyWithdrawableBalanceGwei
        restakedExecutionLayerGwei -= amountGwei;
        instantlyWithdrawableBalanceGwei += amountGwei;
        // mark amountGwei as having been rolled over
        rollableBalanceGwei -= amountGwei;
        // pay penalties as much as possible to prevent podOwner from instantly withdrawing despite having any existing unpaid penalties
        _payOffPenalties();
    }

    /**
     * @notice Transfers `amountWei` in ether from this contract to the specified `recipient` address
     * @notice Called by EigenPodManager to withdrawBeaconChainETH that has been added to the EigenPod's balance due to a withdrawal from the beacon chain.
     * @dev Called during withdrawal or slashing.
     * @dev Note that this function is marked as non-reentrant to prevent the recipient calling back into it
     */
    function withdrawRestakedBeaconChainETH(
        address recipient,
        uint256 amountWei
    )
        external
        onlyEigenPodManager
        nonReentrant
    {
        // reduce the restakedExecutionLayerGwei
        restakedExecutionLayerGwei -= uint64(amountWei / GWEI_TO_WEI);
        
        // transfer ETH directly from pod to `recipient`
        Address.sendValue(payable(recipient), amountWei);

        emit RestakedBeaconChainETHWithdrawn(recipient, amountWei);
    }

    /**
     * @notice Pays off existing penalties due to overcommitting to EigenLayer. Funds for paying penalties are deducted:
     *         1) first, from the execution layer ETH that is restaked in EigenLayer, because 
     *            it is the ETH that is actually supposed to be restaked
     *         2) second, from the instantlyWithdrawableBalanceGwei, to avoid allowing instant withdrawals
     *            from instantlyWithdrawableBalanceGwei, in case the balance of the contract is not enough 
     *            to cover the entire penalty
     */
    function payOffPenalties() external {
        _payOffPenalties();
    }

    // VIEW FUNCTIONS

    /// @return claim is the partial withdrawal claim at the provided index
    function getPartialWithdrawalClaim(uint256 index) external view returns(PartialWithdrawalClaim memory) {
        PartialWithdrawalClaim memory claim = partialWithdrawalClaims[index];
        return claim;
    }

    /// @return length : the number of partial withdrawal claims ever made for this EigenPod
    function getPartialWithdrawalClaimsLength() external view returns(uint256) {
        return partialWithdrawalClaims.length;
    }

    // INTERNAL FUNCTIONS
    /**
     * @notice Pays off existing penalties due to overcommitting to EigenLayer. Funds for paying penalties are deducted:
     *         1) first, from the execution layer ETH that is restaked in EigenLayer, because 
     *            it is the ETH that is actually supposed to be restaked
     *         2) second, from the instantlyWithdrawableBalanceGwei, to avoid allowing instant withdrawals
     *            from instantlyWithdrawableBalanceGwei, in case the balance of the contract is not enough 
     *            to cover the entire penalty
     */
    function _payOffPenalties() internal {
        uint64 penaltiesDueToOvercommittingGweiMemory = penaltiesDueToOvercommittingGwei;
        if (penaltiesDueToOvercommittingGweiMemory != 0) {
            uint64 restakedExecutionLayerGweiMemory = restakedExecutionLayerGwei;
            // if restakedExecutionLayerETH is enough to cover all penalties, penalize all that is necessary and return early
            if (penaltiesDueToOvercommittingGweiMemory <= restakedExecutionLayerGweiMemory) {
                eigenPodManager.payPenalties{value: uint256(penaltiesDueToOvercommittingGweiMemory) * uint256(GWEI_TO_WEI)}(podOwner);
                restakedExecutionLayerGwei = restakedExecutionLayerGweiMemory - penaltiesDueToOvercommittingGweiMemory;
                penaltiesDueToOvercommittingGwei = 0;
                return;
            }

            /// otherwise, remove restakedExecutionLayerGwei from `penaltiesDueToOvercommittingGweiMemory` and set restakedExecutionLayerGwei to zero
            /// i.e. spend all of restakedExecutionLayerGwei to pay down what it can
            uint64 amountPenaltiesToPayGwei = restakedExecutionLayerGweiMemory;
            penaltiesDueToOvercommittingGweiMemory -= restakedExecutionLayerGweiMemory;
            restakedExecutionLayerGwei = 0;

            // next, check if instantlyWithdrawableBalanceGwei is enough to cover the remaining penalties
            uint64 instantlyWithdrawableBalanceGweiMemory = instantlyWithdrawableBalanceGwei;
            // if (restakedExecutionLayerGwei + instantlyWithdrawableBalanceGwei) is enough to cover all penalties, then penalize all that is necessary and return early
            if (penaltiesDueToOvercommittingGweiMemory <= instantlyWithdrawableBalanceGweiMemory) {
                eigenPodManager.payPenalties{value: uint256(penaltiesDueToOvercommittingGwei) * uint256(GWEI_TO_WEI)}(podOwner);
                // allow this amount to be rolled over from restakedExecutionLayerGwei to instantlyWithdrawableBalanceGwei if penalties are ever fully paid in the future
                rollableBalanceGwei += penaltiesDueToOvercommittingGweiMemory;
                instantlyWithdrawableBalanceGwei = instantlyWithdrawableBalanceGweiMemory - penaltiesDueToOvercommittingGweiMemory;
                penaltiesDueToOvercommittingGwei = 0;
                return;
            }

            // if (restakedExecutionLayerGwei + instantlyWithdrawableBalanceGwei) is not enough to cover all penalties, then send it all
            amountPenaltiesToPayGwei += instantlyWithdrawableBalanceGweiMemory;
            eigenPodManager.payPenalties{value: uint256(amountPenaltiesToPayGwei) * uint256(GWEI_TO_WEI)}(podOwner);

            // allow this amount to be rolled over from restakedExecutionLayerGwei to instantlyWithdrawableBalanceGwei if penalties are ever fully paid in the future
            rollableBalanceGwei += instantlyWithdrawableBalanceGweiMemory;
            instantlyWithdrawableBalanceGwei = 0;
            penaltiesDueToOvercommittingGwei -= amountPenaltiesToPayGwei;
        }
    }

    function _podWithdrawalCredentials() internal view returns(bytes memory) {
        return abi.encodePacked(bytes1(uint8(1)), bytes11(0), address(this));
    }

}