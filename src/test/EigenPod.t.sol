// //SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../contracts/interfaces/IEigenPod.sol";
import "./utils/BeaconChainUtils.sol";
import "./EigenLayrDeployer.t.sol";
import "./mocks/MiddlewareRegistryMock.sol";
import "./mocks/ServiceManagerMock.sol";

contract EigenPodTests is BeaconChainProofUtils, DSTest {
    using BytesLib for bytes;

    uint256 internal constant GWEI_TO_WEI = 1e9;

    bytes pubkey = hex"88347ed1c492eedc97fc8c506a35d44d81f27a0c7a1c661b35913cfd15256c0cccbd34a83341f505c7de2983292f2cab";
    uint40 validatorIndex = 0;
    //hash tree root of list of validators
    bytes32 validatorTreeRoot;

    //hash tree root of individual validator container
    bytes32 validatorRoot;

    address podOwner = address(42000094993494);

    Vm cheats = Vm(HEVM_ADDRESS);
    EigenLayrDelegation public delegation;
    IInvestmentManager public investmentManager;
    Slasher public slasher;
    PauserRegistry public pauserReg;

    ProxyAdmin public eigenLayrProxyAdmin;
    IBLSPublicKeyCompendium public blsPkCompendium;
    IEigenPodManager public eigenPodManager;
    IEigenPod public podImplementation;
    IETHPOSDeposit public ethPOSDeposit;
    IBeacon public eigenPodBeacon;
    IBeaconChainOracle public beaconChainOracle;
    MiddlewareRegistryMock public generalReg1;
    ServiceManagerMock public generalServiceManager1;
    address[] public slashingContracts;
    address pauser = address(69);
    address unpauser = address(489);
    address podManagerAddress = 0x212224D2F2d262cd093eE13240ca4873fcCBbA3C;
    uint256 stakeAmount = 32e18;

    modifier fuzzedAddress(address addr) virtual {
        cheats.assume(addr != address(0));
        cheats.assume(addr != address(eigenLayrProxyAdmin));
        cheats.assume(addr != address(investmentManager));
        cheats.assume(addr != podOwner);
        _;
    }


    uint32 PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD = 7 days / 12 seconds;
    uint256 REQUIRED_BALANCE_WEI = 31.4 ether;
    uint64 MIN_FULL_WITHDRAWAL_AMOUNT_GWEI = 1 ether / 1e9;

    //performs basic deployment before each test
    function setUp() public {
        // deploy proxy admin for ability to upgrade proxy contracts
        eigenLayrProxyAdmin = new ProxyAdmin();

        // deploy pauser registry
        pauserReg = new PauserRegistry(pauser, unpauser);

        blsPkCompendium = new BLSPublicKeyCompendium();

        /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        EmptyContract emptyContract = new EmptyContract();
        delegation = EigenLayrDelegation(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );
        investmentManager = InvestmentManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );
        slasher = Slasher(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );

        beaconChainOracle = new BeaconChainOracleMock();

        ethPOSDeposit = new ETHPOSDepositMock();
        podImplementation = new EigenPod(
                ethPOSDeposit, 
                PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD, 
                REQUIRED_BALANCE_WEI,
                MIN_FULL_WITHDRAWAL_AMOUNT_GWEI
        );

        eigenPodBeacon = new UpgradeableBeacon(address(podImplementation));

        // this contract is deployed later to keep its address the same (for these tests)
        eigenPodManager = EigenPodManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
        );

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        EigenLayrDelegation delegationImplementation = new EigenLayrDelegation(investmentManager, slasher);
        InvestmentManager investmentManagerImplementation = new InvestmentManager(delegation, eigenPodManager, slasher);
        Slasher slasherImplementation = new Slasher(investmentManager, delegation);
        EigenPodManager eigenPodManagerImplementation = new EigenPodManager(ethPOSDeposit, eigenPodBeacon, investmentManager, slasher);

        //ensuring that the address of eigenpodmanager doesn't change
        bytes memory code = address(eigenPodManager).code;
        cheats.etch(podManagerAddress, code);
        eigenPodManager = IEigenPodManager(podManagerAddress);

        address initialOwner = address(this);
        // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(delegation))),
            address(delegationImplementation),
            abi.encodeWithSelector(EigenLayrDelegation.initialize.selector, pauserReg, initialOwner)
        );
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(investmentManager))),
            address(investmentManagerImplementation),
            abi.encodeWithSelector(InvestmentManager.initialize.selector, pauserReg, initialOwner)
        );
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(slasher))),
            address(slasherImplementation),
            abi.encodeWithSelector(Slasher.initialize.selector, pauserReg, initialOwner)
        );
        eigenLayrProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(eigenPodManager))),
            address(eigenPodManagerImplementation),
            abi.encodeWithSelector(EigenPodManager.initialize.selector, beaconChainOracle, initialOwner)
        );
        generalServiceManager1 = new ServiceManagerMock(investmentManager);

        generalReg1 = new MiddlewareRegistryMock(
             generalServiceManager1,
             investmentManager
        );

        cheats.deal(address(podOwner), stakeAmount);        
    }

    function testDeployAndVerifyNewEigenPod(bytes memory signature, bytes32 depositDataRoot) public {
        beaconChainOracle.setBeaconChainStateRoot(0xaf3bf0770df5dd35b984eda6586e6f6eb20af904a5fb840fe65df9a6415293bd);
        _testDeployAndVerifyNewEigenPod(podOwner, signature, depositDataRoot, false);
    }

    //test freezing operator after a beacon chain slashing event
    function testUpdateSlashedBeaconBalance(bytes memory signature, bytes32 depositDataRoot) public {
        //make initial deposit
        testDeployAndVerifyNewEigenPod(signature, depositDataRoot);

        //get updated proof, set beaconchain state root
        (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getSlashedDepositProof();

        beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);
        

        IEigenPod eigenPod;
        eigenPod = eigenPodManager.getPod(podOwner);
        
        bytes32 validatorIndexBytes = bytes32(uint256(validatorIndex));
        bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);
        eigenPod.verifyOvercommittedStake(0, proofs, validatorContainerFields, 0);
        
        uint256 beaconChainETHShares = investmentManager.investorStratShares(podOwner, investmentManager.beaconChainETHStrategy());

        require(beaconChainETHShares == 0, "investmentManager shares not updated correctly");
    }

    //test deploying an eigen pod with mismatched withdrawal credentials between the proof and the actual pod's address
    function testDeployNewEigenPodWithWrongWithdrawalCreds(address wrongWithdrawalAddress, bytes memory signature, bytes32 depositDataRoot) public {
        IEigenPod newPod;
        newPod = eigenPodManager.getPod(podOwner);
        // make sure that wrongWithdrawalAddress is not set to actual pod address
        cheats.assume(wrongWithdrawalAddress != address(newPod));
        
        (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getInitialDepositProof();
        beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);


        cheats.startPrank(podOwner);
        eigenPodManager.stake{value: stakeAmount}(pubkey, signature, depositDataRoot);
        cheats.stopPrank();

        validatorContainerFields[1] = abi.encodePacked(bytes1(uint8(1)), bytes11(0), wrongWithdrawalAddress).toBytes32(0);

        bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);
        cheats.expectRevert(bytes("BeaconChainProofs.verifyValidatorFieldsOneShot: Invalid merkle proof"));
        newPod.verifyCorrectWithdrawalCredentials(validatorIndex, proofs, validatorContainerFields);
    }

    //test that when withdrawal credentials are verified more than once, it reverts
    function testDeployNewEigenPodWithActiveValidator(bytes memory signature, bytes32 depositDataRoot) public {
        (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getInitialDepositProof();
        beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);        

        cheats.startPrank(podOwner);
        eigenPodManager.stake{value: stakeAmount}(pubkey, signature, depositDataRoot);
        cheats.stopPrank();

        IEigenPod newPod;
        newPod = eigenPodManager.getPod(podOwner);

        bytes32 validatorIndexBytes = bytes32(uint256(validatorIndex));
        bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);
        newPod.verifyCorrectWithdrawalCredentials(validatorIndex, proofs, validatorContainerFields);

        cheats.expectRevert(bytes("EigenPod.verifyCorrectWithdrawalCredentials: Validator not inactive"));
        newPod.verifyCorrectWithdrawalCredentials(validatorIndex, proofs, validatorContainerFields);
    }

    function testVerifyWithdrawalProofs() public {
                bytes32[] memory withdrawalFields;

                //getting proof for withdrawal from beacon chain
                (
                    withdrawalFields, 
                    beaconStateRoot, 
                    beaconStateMerkleProofForExecutionPayloadHeader, 
                    executionPayloadHeaderProofForWithdrawalProof, 
                    withdrawalMerkleProof
                ) = getWithdrawalProof();



                beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);
                bytes memory withdrawalProof = abi.encodePacked(
                                        withdrawalMerkleProof,
                                        executionPayloadHeaderProofForWithdrawalProof,
                                        beaconStateMerkleProofForExecutionPayloadHeader 
                                    );

                bytes memory historicalStateProof;

                Relayer relay = new Relayer();
                relay.verifyWithdrawalProofsHelp(
                    uint40(0),
                    beaconStateRoot,
                    historicalStateProof,
                    withdrawalProof,
                    withdrawalFields
                );
        
    }

    function getBeaconChainETHShares(address staker) internal returns(uint256) {
        return investmentManager.investorStratShares(staker, investmentManager.beaconChainETHStrategy());
    }

    // TEST CASES:

    // 1. Double withdrawal credential
    // Test: Submit same withdrawal credential proof twice.
    // Expected Behaviour: Should revert with a helpful message the second time

    function testProveWithdrawalCredentialsTwice(IEigenPod pod, uint40 validatorIndex) internal {
        testProveSingleWithdrawalCredential(pod, validatorIndex);
        cheats.expectRevert(bytes("EigenPod.verifyCorrectWithdrawalCredentials: Validator not inactive"));
        testProveSingleWithdrawalCredential(pod, validatorIndex);
    }

    // 2. Double full withdrawal
    // Test: Submit same full withdrawal proof twice.
    // Expected Behaviour: Should revert with a helpful message the second time

    // 3. Single withdrawal credential
    // Test: Owner proves an withdrawal credential.
    // Expected Behaviour: beaconChainETH shares should increment by REQUIRED_BALANCE_WEI
    //                     validator status should be marked as ACTIVE

    function testProveSingleWithdrawalCredential(IEigenPod pod, uint40 validatorIndex) internal {
        // get beaconChainETH shares
        uint256 beaconChainETHBefore = getBeaconChainETHShares(pod.podOwner());

        // pointed withdrawal credential

        uint256 beaconChainETHAfter = getBeaconChainETHShares(pod.podOwner());
        assertTrue(beaconChainETHAfter - beaconChainETHBefore == pod.REQUIRED_BALANCE_WEI());
        assertTrue(pod.validatorStatus(validatorIndex) == IEigenPod.VALIDATOR_STATUS.ACTIVE);
    }

    // 4. Happy case full withdrawal
    // Setup: Run (3). 
    // Test: Credit the pod balance with AMOUNT (>= REQUIRED_BALANCE_GWEI) gwei and then owner submit 
    //       full withdrawal proof for validator from (3).
    // Expected Behaviour: restakedExecutionLayerBalanceGwei should be REQUIRED_BALANCE_GWEI
    //                     instantlyWithdrawableBalanceGwei should be AMOUNT - REQUIRED_BALANCE_GWEI
    //                     validator status should be marked as WITHDRAWN

    function testSufficientFullWithdrawal(IEigenPod pod, uint40 validatorIndex, uint64 withdrawalAmountGwei) internal {
        cheats.assume(pod.restakedExecutionLayerGwei() == 0);
        cheats.assume(pod.penaltiesDueToOvercommittingGwei() == 0);
        // withdrawal amount must be sufficient
        cheats.assume(withdrawalAmountGwei >= pod.REQUIRED_BALANCE_GWEI() && withdrawalAmountGwei <= 33 ether);

        uint64 instantlyWithdrawableBalanceGweiBefore = pod.instantlyWithdrawableBalanceGwei();
        uint64 rolleableBalanceBefore = pod.rollableBalanceGwei();

        cheats.deal(address(pod), address(pod).balance + withdrawalAmountGwei * GWEI_TO_WEI);

        // prove sufficient full withdrawal

        assertTrue(pod.restakedExecutionLayerGwei() == pod.REQUIRED_BALANCE_GWEI());
        assertTrue(pod.instantlyWithdrawableBalanceGwei() - instantlyWithdrawableBalanceGweiBefore == withdrawalAmountGwei - pod.REQUIRED_BALANCE_GWEI());
        assertTrue(pod.rollableBalanceGwei() == rolleableBalanceBefore);
        assertTrue(pod.validatorStatus(validatorIndex) == IEigenPod.VALIDATOR_STATUS.WITHDRAWN);
    }

    // 5. Prove overcommitted balance
    // Setup: Run (3). 
    // Test: Watcher proves an overcommitted balance for validator from (3).
    // Expected Behaviour: beaconChainETH shares should decrement by REQUIRED_BALANCE_WEI
    //                     penaltiesDueToOvercommittingGwei should increase by OVERCOMMITMENT_PENALTY_AMOUNT_GWEI
    //                     validator status should be marked as OVERCOMMITTED

    function testProveOverCommittedBalance(IEigenPod pod, uint40 validatorIndex) internal {
        testProveSingleWithdrawalCredential(pod,  validatorIndex);
        // get beaconChainETH shares
        uint256 beaconChainETHBefore = getBeaconChainETHShares(pod.podOwner());
        uint64 penaltiesDueToOvercommittingGweiBefore = pod.penaltiesDueToOvercommittingGwei();

        // prove overcommitted balance

        assertTrue(beaconChainETHBefore - getBeaconChainETHShares(pod.podOwner()) == pod.REQUIRED_BALANCE_GWEI());
        assertTrue(pod.penaltiesDueToOvercommittingGwei() - penaltiesDueToOvercommittingGweiBefore == pod.OVERCOMMITMENT_PENALTY_AMOUNT_GWEI());
        assertTrue(pod.validatorStatus(validatorIndex) == IEigenPod.VALIDATOR_STATUS.OVERCOMMITTED);
    }
    
    // 6. Insufficient full withdrawal for active validator
    // Setup: Run (3).
    // Test: Credit the pod balance with AMOUNT (< REQUIRED_BALANCE_GWEI) gwei and then owner submit 
    //       full withdrawal proof for validator from (3) whose balance is overcommitted but has not been marked as such.    
    // Expected Behaviour: beaconChainETH shares should decrement by REQUIRED_BALANCE_WEI
    //                     penaltiesDueToOvercommittingGwei should be OVERCOMMITMENT_PENALTY_AMOUNT_GWEI - AMOUNT
    //                     restakedExecutionLayerBalanceGwei should be 0
    //                     instantlyWithdrawableBalanceGwei should be 0
    //                     validator status should be marked as OVERCOMMITTED

    function testInsufficientFullWithdrawalForActiveValidator(IEigenPod pod, uint40 validatorIndex, uint64 withdrawalAmountGwei) internal {
        testProveSingleWithdrawalCredential(pod, validatorIndex);
        // the validator must be active, not proven overcommitted
        cheats.assume(pod.validatorStatus(validatorIndex) == IEigenPod.VALIDATOR_STATUS.ACTIVE);
        cheats.assume(pod.restakedExecutionLayerGwei() == 0);
        cheats.assume(pod.penaltiesDueToOvercommittingGwei() == 0);
        // withdrawal amount must be sufficient
        cheats.assume(withdrawalAmountGwei < pod.REQUIRED_BALANCE_GWEI());
        // get beaconChainETH shares
        uint256 beaconChainETHBefore = getBeaconChainETHShares(pod.podOwner());
        uint64 instantlyWithdrawableBalanceGweiBefore = pod.instantlyWithdrawableBalanceGwei();
        uint64 rolleableBalanceBefore = pod.rollableBalanceGwei();

        cheats.deal(address(pod), address(pod).balance + withdrawalAmountGwei * GWEI_TO_WEI);

        // prove insufficient full withdrawal

        assertTrue(beaconChainETHBefore - getBeaconChainETHShares(pod.podOwner()) == pod.REQUIRED_BALANCE_GWEI());
        // check that penalties were paid off correctly
        assertTrue(pod.penaltiesDueToOvercommittingGwei() == pod.OVERCOMMITMENT_PENALTY_AMOUNT_GWEI() - withdrawalAmountGwei);
        assertTrue(pod.restakedExecutionLayerGwei() == 0);
        assertTrue(pod.instantlyWithdrawableBalanceGwei() == instantlyWithdrawableBalanceGweiBefore);
        assertTrue(pod.rollableBalanceGwei() == rolleableBalanceBefore);
        assertTrue(pod.validatorStatus(validatorIndex) == IEigenPod.VALIDATOR_STATUS.WITHDRAWN);
    }

    // 7. Pay off penalties with sufficient full withdrawal
    // Test: Run (5). Then prove a sufficient withdrawal.
    // Expected Behaviour: penaltiesDueToOvercommittingGwei should be 0
    //                     restakedExecutionLayerBalanceGwei should be 0
    //                     instantlyWithdrawableBalanceGwei should be AMOUNT - REQUIRED_BALANCE_GWEI
    //                     rollableBalanceGwei should be 0
    //                     validator status should be marked as WITHDRWAN

    function testPayOffPenaltiesWithSufficientWithdrawal(IEigenPod pod, uint40 validatorIndex, uint64 withdrawalAmountGwei) internal {
        cheats.assume(pod.OVERCOMMITMENT_PENALTY_AMOUNT_GWEI() == pod.REQUIRED_BALANCE_GWEI());
        cheats.assume(pod.restakedExecutionLayerGwei() == 0);
        cheats.assume(pod.penaltiesDueToOvercommittingGwei() == 0);
        // withdrawal amount must be sufficient
        cheats.assume(withdrawalAmountGwei >= pod.REQUIRED_BALANCE_GWEI() && withdrawalAmountGwei <= 33 ether);

        testProveOverCommittedBalance(pod, validatorIndex);

        uint64 instantlyWithdrawableBalanceGweiBefore = pod.instantlyWithdrawableBalanceGwei();
        uint64 rolleableBalanceBefore = pod.rollableBalanceGwei();

        cheats.deal(address(pod), address(pod).balance + withdrawalAmountGwei * GWEI_TO_WEI);

        // prove sufficient full withdrawal

        assertTrue(pod.penaltiesDueToOvercommittingGwei() == 0);
        assertTrue(pod.restakedExecutionLayerGwei() == 0);
        assertTrue(pod.instantlyWithdrawableBalanceGwei() - instantlyWithdrawableBalanceGweiBefore == withdrawalAmountGwei - pod.REQUIRED_BALANCE_GWEI());
        assertTrue(pod.rollableBalanceGwei() == rolleableBalanceBefore);
        assertTrue(pod.validatorStatus(validatorIndex) == IEigenPod.VALIDATOR_STATUS.WITHDRAWN);
    }

    function testPayOffMultiplePenaltiesWithSufficientWithdrawal(IEigenPod pod, uint40 validatorIndex1, uint40 validatorIndex2, uint64 withdrawalAmountGwei) internal {
        cheats.assume(pod.OVERCOMMITMENT_PENALTY_AMOUNT_GWEI() == pod.REQUIRED_BALANCE_GWEI());
        cheats.assume(pod.restakedExecutionLayerGwei() == 0);
        cheats.assume(pod.instantlyWithdrawableBalanceGwei() == 0);
        cheats.assume(pod.penaltiesDueToOvercommittingGwei() == 0);
        // withdrawal amount must be sufficient
        cheats.assume(withdrawalAmountGwei >= pod.REQUIRED_BALANCE_GWEI() && withdrawalAmountGwei <= 33 ether);

        testProveOverCommittedBalance(pod, validatorIndex1);
        testProveOverCommittedBalance(pod, validatorIndex2);

        uint64 rolleableBalanceBefore = pod.rollableBalanceGwei();

        cheats.deal(address(pod), address(pod).balance + withdrawalAmountGwei * GWEI_TO_WEI);

        // prove sufficient full withdrawal for validatorIndex1

        assertTrue(pod.penaltiesDueToOvercommittingGwei() == 2 * pod.OVERCOMMITMENT_PENALTY_AMOUNT_GWEI() - withdrawalAmountGwei);
        assertTrue(pod.restakedExecutionLayerGwei() == 0);
        assertTrue(pod.instantlyWithdrawableBalanceGwei() == 0);
        assertTrue(pod.rollableBalanceGwei() == rolleableBalanceBefore + withdrawalAmountGwei - pod.REQUIRED_BALANCE_GWEI());
        assertTrue(pod.validatorStatus(validatorIndex1) == IEigenPod.VALIDATOR_STATUS.WITHDRAWN);
    }

    // 8. Test instant withdrawals after a bunch of sufficient full withdrawals
    // Setup: Run (3).
    // Test: Run n sufficient withdrawals. Withdraw withdrawAmountGwei worth of instantlyWithdrawableBalanceGwei.
    // Expected Behaviour: restakedExecutionLayerBalanceGwei should stay the same
    //                     instantlyWithdrawableBalanceGwei_BEFORE should be (AMOUNT - REQUIRED_BALANCE_GWEI) * n
    //                     instantlyWithdrawableBalanceGwei should be instantlyWithdrawableBalanceGwei_BEFORE - withdrawAmountGwei
    //                     pod owner balance should increase by withdrawAmountGwei

    // 9. Roll over penalties paid from instantly withdrawable funds after sufficient withdrawals
    // Setup: Run testPayOffMultiplePenaltiesWithSufficientWithdrawal. 
    // Test: Run enough sufficient withdrawals to get a positive restakedExuctionLayerGwei. 
    //       Roll over toRollAmountGwei from rollableBalanceGwei to instantlyWithdrawableBalanceGwei.
    // Expected Behaviour: restakedExuctionLayerGwei should decrement by toRollAmountGwei
    //                     instantlyWithdrawableBalanceGwei should increment by toRollAmountGwei
    //                     rollableBalanceGwei should decrement toRollAmountGwei

    // 10. Fail to roll over rollable balance when all penalties are not paid
    // Setup: Run (5), run (6). 
    // Test: Roll over toRollAmountGwei from rollableBalanceGwei to instantlyWithdrawableBalanceGwei.
    // Expected Behaviour: Reverts due to penalties not being paid off

    // 11. Make partial withdrawal claim
    // Test: Credit balance with PARTIAL_AMOUNT_GWEI gwei and record a balance snapshot with an expire block far in the future
    // Expected Behaviour: Should append a pending a partial withdrawal claim for 
    //                     (pod.balance - restakedExecutionLayerGwei - instantlyWithdrawableBalanceGwei) amount 
    //                     at block.number to the end of the partial withdrawal list

    function testMakePartialWithdrawalClaim(IEigenPod pod, uint40 validatorIndex, uint64 partialWithdrawalAmountGwei) internal {
        uint64 restakedExectionLayerGweiBefore = pod.restakedExecutionLayerGwei();
        uint64 instantlyWithdrawableBalanceGweiBefore = pod.instantlyWithdrawableBalanceGwei();
        uint256 lengthBefore = pod.getPartialWithdrawalClaimsLength();

        cheats.deal(address(pod), address(pod).balance + partialWithdrawalAmountGwei * GWEI_TO_WEI);

        cheats.prank(pod.podOwner());
        pod.recordPartialWithdrawalClaim(uint32(block.number + 100));

        IEigenPod.PartialWithdrawalClaim memory claim = pod.getPartialWithdrawalClaim(pod.getPartialWithdrawalClaimsLength() - 1);

        assertTrue(claim.status == IEigenPod.PARTIAL_WITHDRAWAL_CLAIM_STATUS.PENDING);
        assertTrue(claim.partialWithdrawalAmountGwei == uint64(address(pod).balance / GWEI_TO_WEI) - restakedExectionLayerGweiBefore - instantlyWithdrawableBalanceGweiBefore);
        assertTrue(pod.getPartialWithdrawalClaimsLength() == lengthBefore + 1);

    }

    // 12. Expired partial withdrawal claim
    // Setup: Credit balance with PARTIAL_AMOUNT gwei
    // Test: Record a balance snapshot with an expire block in the past
    // Expected Behaviour: Reverts due to expiry

    // 13. Premature partial withdrawal claim redemption
    // Setup: Run (11).
    // Test: Pod owner attempts to redeem partial withdrawals after a duration of blocks less than PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS
    // Expected Behaviour: Reverts because fraud proof period has not passed

    // 14. Fraudulent partial withdrawal
    // Setup: Credit balance with AMOUNT (>= REQUIRED_BALANCE_GWEI). Run (11).
    // Test: Watcher proves withdrawal of AMOUNT before the block in which (11) occured.
    // Expected Behaviour: Partial withdrawal should be marked as failed.

    // 15. Redeem fraudulent partial withdrawal
    // Setup: Run (14).
    // Test: Pod owner attempts to redeem partial withdrawal
    // Expected Behaviour: Reverts because withdrawal is not pending

    // 16. Test happy partial withdrawal
    // Setup: Run (11). 
    // Test: PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS pass. Pod owner attempts to redeem partial withdrawal
    // Expected Behaviour: pod.balance should be decremented by PARTIAL_AMOUNT_GWEI gwei
    //                     podOwner balance should be incremented by PARTIAL_AMOUNT_GWEI gwei
    //                     partial withdrawal should be marked as redeemed

    // 17. Double partial withdrawal
    // Setup: Run (11). 
    // Test: before PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS have passed, run (11).
    // Expected Behaviour: Revert with partial withdrawal already exists

    // 18. Pay penalties from partial withdrawal
    // Setup: Run (5), run (11). 
    // Test: PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS pass. Pod owner attempts to redeem partial withdrawal
    // Expected Behaviour: if PARTIAL_AMOUNT_GWEI >= OVERCOMMITMENT_PENALTY_AMOUNT_GWEI
    //                          penaltiesDueToOvercommittingGwei should be 0
    //                          podOwner.balance should increment by PARTIAL_AMOUNT_GWEI - OVERCOMMITMENT_PENALTY_AMOUNT_GWEI
    //                     else
    //                          penaltiesDueToOvercommittingGwei should be OVERCOMMITMENT_PENALTY_AMOUNT_GWEI - PARTIAL_AMOUNT_GWEI
    //                          podOwner.balance should stay the same
    //                     write relevant test cases here
    //                     pod.balance should decrement by PARTIAL_AMOUNT_GWEI 
    //                     rollableBalanceGwei should increment by PARTIAL_AMOUNT_GWEI 

    // 19. Pay penalties from partial withdrawal and then roll over balance
    // Setup: Run (18).
    // Test: Run enough full withdrawals until all penalties are paid. Attempt to roll over toRollAmountGwei.
    // Expected Behaviour: Math is more complicated here, but keep track of rollable balance and make sure it
    //                     always accounts for the parital withdrawal

    // 20. Withdraw penalties
    // Setup: Run (7).
    // Test: IM owner attempts to withdraw amount penalties for pod to recipient.
    // Expected Behaviour: EigenPodManager.balance should decrement by amount
    //                     recipient.balance should increment by amount 

    // These seem like the building blocks. would be good to combine them in funky ways too.

    // // Withdraw eigenpods balance to an EOA
    // function testEigenPodsQueuedWithdrawalEOA(address operator, bytes memory signature, bytes32 depositDataRoot) public fuzzedAddress(operator){
    //     //make initial deposit
    //     testDeployAndVerifyNewEigenPod(signature, depositDataRoot);

    //     //*************************DELEGATION+REGISTRATION OF OPERATOR******************************//
    //     _testDelegation(operator, podOwner);


    //     cheats.startPrank(operator);
    //     investmentManager.slasher().optIntoSlashing(address(generalServiceManager1));
    //     cheats.stopPrank();


    //     generalReg1.registerOperator(operator, uint32(block.timestamp) + 3 days);
    //     //*********************************************************************************************//

    //     {
    //             IEigenPod newPod;
    //             newPod = eigenPodManager.getPod(podOwner);
    //             //adding balance to pod to simulate a withdrawal
    //             cheats.deal(address(newPod), stakeAmount);

    //             //getting proof for withdrawal from beacon chain
    //             (
    //                 withdrawalContainerFields, 
    //                 beaconStateRoot, 
    //                 beaconStateMerkleProofForExecutionPayloadHeader, 
    //                 executionPayloadHeaderRoot, 
    //                 executionPayloadHeaderProofForWithdrawalProof, 
    //                 withdrawalTreeRoot,
    //                 withdrawalMerkleProof,
    //                 withdrawalRoot
    //             ) = getWithdrawalProof();

    //             beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);
    //             bytes memory proofs = abi.encodePacked(
    //                                     executionPayloadHeaderRoot, 
    //                                     beaconStateMerkleProofForExecutionPayloadHeader, 
    //                                     withdrawalTreeRoot, 
    //                                     executionPayloadHeaderProofForWithdrawalProof,
    //                                     withdrawalRoot,
    //                                     bytes32(uint256(0)), 
    //                                     withdrawalRoot
    //                                 );
    //             newPod.verifyBeaconChainFullWithdrawal(validatorIndex, proofs, withdrawalContainerFields,  0);
    //     }
        
        // IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        // IERC20[] memory tokensArray = new IERC20[](1);
        // uint256[] memory shareAmounts = new uint256[](1);
        // uint256[] memory strategyIndexes = new uint256[](1);
        // IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce =
        //     IInvestmentManager.WithdrawerAndNonce({withdrawer: podOwner, nonce: 0});
        // bool undelegateIfPossible = false;
        // {
        //     strategyArray[0] = investmentManager.beaconChainETHStrategy();
        //     shareAmounts[0] = REQUIRED_BALANCE_WEI;
        //     strategyIndexes[0] = 0;
        // }


        // uint256 podOwnerSharesBefore = investmentManager.investorStratShares(podOwner, investmentManager.beaconChainETHStrategy());
        

        // cheats.warp(uint32(block.timestamp) + 1 days);
        // cheats.roll(uint32(block.timestamp) + 1 days);

        // cheats.startPrank(podOwner);
        // investmentManager.queueWithdrawal(strategyIndexes, strategyArray, tokensArray, shareAmounts, podOwner, undelegateIfPossible);
        // cheats.stopPrank();
        // uint32 queuedWithdrawalStartBlock = uint32(block.number);

        // //*************************DELEGATION/Stake Update STUFF******************************//
        // //now withdrawal block time is before deregistration
        // cheats.warp(uint32(block.timestamp) + 2 days);
        // cheats.roll(uint32(block.timestamp) + 2 days);
        
        // generalReg1.deregisterOperator(operator);

        // //warp past the serve until time, which is 3 days from the beginning.  THis puts us at 4 days past that point
        // cheats.warp(uint32(block.timestamp) + 4 days);
        // cheats.roll(uint32(block.timestamp) + 4 days);
        // //*************************************************************************//

        // uint256 podOwnerSharesAfter = investmentManager.investorStratShares(podOwner, investmentManager.beaconChainETHStrategy());

        // require(podOwnerSharesBefore - podOwnerSharesAfter == REQUIRED_BALANCE_WEI, "delegation shares not updated correctly");

        // address delegatedAddress = delegation.delegatedTo(podOwner);
        // IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal = IInvestmentManager.QueuedWithdrawal({
        //     strategies: strategyArray,
        //     tokens: tokensArray,
        //     shares: shareAmounts,
        //     depositor: podOwner,
        //     withdrawerAndNonce: withdrawerAndNonce,
        //     withdrawalStartBlock: queuedWithdrawalStartBlock,
        //     delegatedAddress: delegatedAddress
        // });

        // uint256 podOwnerBalanceBefore = podOwner.balance;
        // uint256 middlewareTimesIndex = 1;
        // bool receiveAsTokens = true;
        // cheats.startPrank(podOwner);

        // investmentManager.completeQueuedWithdrawal(queuedWithdrawal, middlewareTimesIndex, receiveAsTokens);

        // cheats.stopPrank();

        // require(podOwner.balance - podOwnerBalanceBefore == shareAmounts[0], "podOwner balance not updated correcty");


    //} 

    // simply tries to register 'sender' as a delegate, setting their 'DelegationTerms' contract in EigenLayrDelegation to 'dt'
    // verifies that the storage of EigenLayrDelegation contract is updated appropriately
    function _testRegisterAsOperator(address sender, IDelegationTerms dt) internal {
        cheats.startPrank(sender);

        delegation.registerAsOperator(dt);
        assertTrue(delegation.isOperator(sender), "testRegisterAsOperator: sender is not a delegate");

        assertTrue(
            delegation.delegationTerms(sender) == dt, "_testRegisterAsOperator: delegationTerms not set appropriately"
        );

        assertTrue(delegation.isDelegated(sender), "_testRegisterAsOperator: sender not marked as actively delegated");
        cheats.stopPrank();
    }

    function _testDelegateToOperator(address sender, address operator) internal {
        //delegator-specific information
        (IInvestmentStrategy[] memory delegateStrategies, uint256[] memory delegateShares) =
            investmentManager.getDeposits(sender);

        uint256 numStrats = delegateShares.length;
        assertTrue(numStrats > 0, "_testDelegateToOperator: delegating from address with no investments");
        uint256[] memory inititalSharesInStrats = new uint256[](numStrats);
        for (uint256 i = 0; i < numStrats; ++i) {
            inititalSharesInStrats[i] = delegation.operatorShares(operator, delegateStrategies[i]);
        }

        cheats.startPrank(sender);
        delegation.delegateTo(operator);
        cheats.stopPrank();

        assertTrue(
            delegation.delegatedTo(sender) == operator,
            "_testDelegateToOperator: delegated address not set appropriately"
        );
        assertTrue(
            delegation.isDelegated(sender),
            "_testDelegateToOperator: delegated status not set appropriately"
        );

        for (uint256 i = 0; i < numStrats; ++i) {
            uint256 operatorSharesBefore = inititalSharesInStrats[i];
            uint256 operatorSharesAfter = delegation.operatorShares(operator, delegateStrategies[i]);
            assertTrue(
                operatorSharesAfter == (operatorSharesBefore + delegateShares[i]),
                "_testDelegateToOperator: delegatedShares not increased correctly"
            );
        }
    }
    function _testDelegation(address operator, address staker)
        internal
    {   
        if (!delegation.isOperator(operator)) {
            _testRegisterAsOperator(operator, IDelegationTerms(operator));
        }

        //making additional deposits to the investment strategies
        assertTrue(delegation.isNotDelegated(staker) == true, "testDelegation: staker is not delegate");
        _testDelegateToOperator(staker, operator);
        assertTrue(delegation.isDelegated(staker) == true, "testDelegation: staker is not delegate");

        IInvestmentStrategy[] memory updatedStrategies;
        uint256[] memory updatedShares;
        (updatedStrategies, updatedShares) =
            investmentManager.getDeposits(staker);
    }

    function _testDeployAndVerifyNewEigenPod(address _podOwner, bytes memory signature, bytes32 depositDataRoot, bool isContract) internal {
        (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getInitialDepositProof();

        //if the _podOwner is a contract, we get the beacon state proof for the contract-specific withdrawal credential
        if(isContract) {
            (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getContractAddressWithdrawalCred();
        }

        cheats.startPrank(_podOwner);
        eigenPodManager.stake{value: stakeAmount}(pubkey, signature, depositDataRoot);
        cheats.stopPrank();

        beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);

        IEigenPod newPod;

        newPod = eigenPodManager.getPod(_podOwner);

        bytes32 validatorIndexBytes = bytes32(uint256(validatorIndex));
        bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);

        newPod.verifyCorrectWithdrawalCredentials(validatorIndex, proofs, validatorContainerFields);

        IInvestmentStrategy beaconChainETHStrategy = investmentManager.beaconChainETHStrategy();

        uint256 beaconChainETHShares = investmentManager.investorStratShares(_podOwner, beaconChainETHStrategy);
        require(beaconChainETHShares == REQUIRED_BALANCE_WEI, "investmentManager shares not updated correctly");
    }

 }


 contract Relayer is Test {
    function verifyWithdrawalProofsHelp(
        uint40 withdrawalIndex,
        bytes32 beaconStateRoot, 
        bytes calldata historicalStateProof, 
        bytes calldata withdrawalProof, 
        bytes32[] calldata withdrawalFields
    ) public {
        BeaconChainProofs.verifyWithdrawalProofs(beaconStateRoot, historicalStateProof, withdrawalProof, withdrawalFields);
    }
 }