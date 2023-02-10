// //SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "../contracts/interfaces/IEigenPod.sol";
import "../contracts/interfaces/IBLSPublicKeyCompendium.sol";
import "../contracts/middleware/BLSPublicKeyCompendium.sol";
import "../contracts/pods/EigenPodPaymentEscrow.sol";
import "./utils/BeaconChainUtils.sol";
import "./utils/ProofParsing.sol";
import "./EigenLayerDeployer.t.sol";
import "./mocks/MiddlewareRegistryMock.sol";
import "./mocks/ServiceManagerMock.sol";
import "../contracts/libraries/BeaconChainProofs.sol";


contract EigenPodTests is BeaconChainProofUtils, ProofParsing, EigenPodPausingConstants {
    using BytesLib for bytes;

    uint256 internal constant GWEI_TO_WEI = 1e9;

    bytes pubkey = hex"88347ed1c492eedc97fc8c506a35d44d81f27a0c7a1c661b35913cfd15256c0cccbd34a83341f505c7de2983292f2cab";
    uint40 validatorIndex0 = 0;
    uint40 validatorIndex1 = 1;
    //hash tree root of list of validators
    bytes32 validatorTreeRoot;

    //hash tree root of individual validator container
    bytes32 validatorRoot;

    address podOwner = address(42000094993494);

    Vm cheats = Vm(HEVM_ADDRESS);
    EigenLayerDelegation public delegation;
    IInvestmentManager public investmentManager;
    Slasher public slasher;
    PauserRegistry public pauserReg;

    ProxyAdmin public eigenLayerProxyAdmin;
    IBLSPublicKeyCompendium public blsPkCompendium;
    IEigenPodManager public eigenPodManager;
    IEigenPod public podImplementation;
    IEigenPodPaymentEscrow public eigenPodPaymentEscrow;
    IETHPOSDeposit public ethPOSDeposit;
    IBeacon public eigenPodBeacon;
    IBeaconChainOracle public beaconChainOracle;
    MiddlewareRegistryMock public generalReg1;
    ServiceManagerMock public generalServiceManager1;
    address[] public slashingContracts;
    address pauser = address(69);
    address unpauser = address(489);
    address podManagerAddress = 0x212224D2F2d262cd093eE13240ca4873fcCBbA3C;
    address podAddress = address(123);
    uint256 stakeAmount = 32e18;
    mapping (address => bool) fuzzedAddressMapping;
    bytes signature;
    bytes32 depositDataRoot;


    modifier fuzzedAddress(address addr) virtual {
        cheats.assume(fuzzedAddressMapping[addr] == false);
        _;
    }


    uint32 PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS = 7 days / 12 seconds;
    uint256 REQUIRED_BALANCE_WEI = 31.4 ether;
    uint64 MIN_FULL_WITHDRAWAL_AMOUNT_GWEI = 1 ether / 1e9;

    //performs basic deployment before each test
    function setUp() public {
        // deploy proxy admin for ability to upgrade proxy contracts
        eigenLayerProxyAdmin = new ProxyAdmin();

        // deploy pauser registry
        pauserReg = new PauserRegistry(pauser, unpauser);

        blsPkCompendium = new BLSPublicKeyCompendium();

        /**
         * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
         * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
         */
        EmptyContract emptyContract = new EmptyContract();
        delegation = EigenLayerDelegation(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );
        investmentManager = InvestmentManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );
        slasher = Slasher(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );
        eigenPodPaymentEscrow = EigenPodPaymentEscrow(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );

        ethPOSDeposit = new ETHPOSDepositMock();
        podImplementation = new EigenPod(
                ethPOSDeposit, 
                eigenPodPaymentEscrow,
                PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS, 
                REQUIRED_BALANCE_WEI,
                MIN_FULL_WITHDRAWAL_AMOUNT_GWEI
        );

        eigenPodBeacon = new UpgradeableBeacon(address(podImplementation));

        // this contract is deployed later to keep its address the same (for these tests)
        eigenPodManager = EigenPodManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayerProxyAdmin), ""))
        );

        // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
        EigenLayerDelegation delegationImplementation = new EigenLayerDelegation(investmentManager, slasher);
        InvestmentManager investmentManagerImplementation = new InvestmentManager(delegation, IEigenPodManager(podManagerAddress), slasher);
        Slasher slasherImplementation = new Slasher(investmentManager, delegation);
        EigenPodManager eigenPodManagerImplementation = new EigenPodManager(ethPOSDeposit, eigenPodBeacon, investmentManager, slasher);

        //ensuring that the address of eigenpodmanager doesn't change
        bytes memory code = address(eigenPodManager).code;
        cheats.etch(podManagerAddress, code);
        eigenPodManager = IEigenPodManager(podManagerAddress);

        beaconChainOracle = new BeaconChainOracleMock();
        EigenPodPaymentEscrow eigenPodPaymentEscrowImplementation = new EigenPodPaymentEscrow(IEigenPodManager(podManagerAddress));

        address initialOwner = address(this);
        // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(delegation))),
            address(delegationImplementation),
            abi.encodeWithSelector(EigenLayerDelegation.initialize.selector, pauserReg, initialOwner)
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(investmentManager))),
            address(investmentManagerImplementation),
            abi.encodeWithSelector(InvestmentManager.initialize.selector, pauserReg, initialOwner, 0)
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(slasher))),
            address(slasherImplementation),
            abi.encodeWithSelector(Slasher.initialize.selector, pauserReg, initialOwner)
        );
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(eigenPodManager))),
            address(eigenPodManagerImplementation),
            abi.encodeWithSelector(EigenPodManager.initialize.selector, beaconChainOracle, initialOwner, pauserReg, 0)
        );
        uint256 initPausedStatus = 0;
        uint256 withdrawalDelayBlocks = PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS;
        eigenLayerProxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(eigenPodPaymentEscrow))),
            address(eigenPodPaymentEscrowImplementation),
            abi.encodeWithSelector(EigenPodPaymentEscrow.initialize.selector, initialOwner, pauserReg, initPausedStatus, withdrawalDelayBlocks)
        );
        generalServiceManager1 = new ServiceManagerMock(slasher);

        generalReg1 = new MiddlewareRegistryMock(
             generalServiceManager1,
             investmentManager
        );

        cheats.deal(address(podOwner), stakeAmount);     

        fuzzedAddressMapping[address(0)] = true;
        fuzzedAddressMapping[address(eigenLayerProxyAdmin)] = true;
        fuzzedAddressMapping[address(investmentManager)] = true;
        fuzzedAddressMapping[address(eigenPodManager)] = true;
        fuzzedAddressMapping[address(delegation)] = true;
        fuzzedAddressMapping[address(slasher)] = true;
        fuzzedAddressMapping[address(generalServiceManager1)] = true;
        fuzzedAddressMapping[address(generalReg1)] = true;

    }

    function testVerifyFullWithdrawal() public {
        //make initial deposit
        bytes32 beaconStateRoot = getBeaconStateRoot();
        bytes32 blockHeaderRoot = getBlockHeaderRoot();
        bytes32 blockBodyRoot = getBlockBodyRoot();
        bytes32 slotRoot = getSlotRoot();

        uint256 validatorIndex = getValidatorIndex(); 
        uint256 withdrawalIndex = getWithdrawalIndex();
        uint256 blockHeaderRootIndex = getBlockHeaderRootIndex();

        blockHeaderProof = getBlockHeaderProof();
        withdrawalProof = getWithdrawalProof();
        slotProof = getSlotProof();
        validatorProof = getValidatorProof();

        withdrawalFields = getWithdrawalFields();   
        validatorFields = getValidatorFields();


        BeaconChainProofs.WithdrawalProofs memory proofs = BeaconChainProofs.WithdrawalProofs(
            abi.encodePacked(blockHeaderProof),
            abi.encodePacked(withdrawalProof),
            abi.encodePacked(slotProof),
            abi.encodePacked(validatorProof),
            uint16(blockHeaderRootIndex),
            uint8(withdrawalIndex),
            uint8(validatorIndex),
            blockHeaderRoot,
            blockBodyRoot,
            slotRoot
        );

        Relayer relay = new Relayer();

        relay.verifySlotAndWithdrawalFields(beaconStateRoot, proofs, withdrawalFields, validatorFields);
    }

    function testDeployAndVerifyNewEigenPod() public returns(IEigenPod){
        beaconChainOracle.setBeaconChainStateRoot(0xaf3bf0770df5dd35b984eda6586e6f6eb20af904a5fb840fe65df9a6415293bd);
        return _testDeployAndVerifyNewEigenPod(podOwner, signature, depositDataRoot, false, validatorIndex0);
    }

    //test freezing operator after a beacon chain slashing event
    function testUpdateSlashedBeaconBalance() public {
        //make initial deposit
        IEigenPod eigenPod = testDeployAndVerifyNewEigenPod();

        //get updated proof, set beaconchain state root
        _proveOvercommittedStake(eigenPod, validatorIndex0);
        
        uint256 beaconChainETHShares = investmentManager.investorStratShares(podOwner, investmentManager.beaconChainETHStrategy());

        require(beaconChainETHShares == 0, "investmentManager shares not updated correctly");
    }

    //test deploying an eigen pod with mismatched withdrawal credentials between the proof and the actual pod's address
    function testDeployNewEigenPodWithWrongWithdrawalCreds(address wrongWithdrawalAddress) public {
        IEigenPod newPod;
        newPod = eigenPodManager.getPod(podOwner);
        // make sure that wrongWithdrawalAddress is not set to actual pod address
        cheats.assume(wrongWithdrawalAddress != address(newPod));
        
        (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) =
            getInitialDepositProof(validatorIndex0);
        beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);


        cheats.startPrank(podOwner);
        eigenPodManager.stake{value: stakeAmount}(pubkey, signature, depositDataRoot);
        cheats.stopPrank();

        validatorContainerFields[1] = abi.encodePacked(bytes1(uint8(1)), bytes11(0), wrongWithdrawalAddress).toBytes32(0);

        bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);
        cheats.expectRevert(bytes("BeaconChainProofs.verifyValidatorFields: Invalid merkle proof"));
        newPod.verifyCorrectWithdrawalCredentials(validatorIndex0, proofs, validatorContainerFields);
    }

    //test that when withdrawal credentials are verified more than once, it reverts
    function testDeployNewEigenPodWithActiveValidator() public {
        (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) =
            getInitialDepositProof(validatorIndex0);
        beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);        

        cheats.startPrank(podOwner);
        eigenPodManager.stake{value: stakeAmount}(pubkey, signature, depositDataRoot);
        cheats.stopPrank();

        IEigenPod newPod;
        newPod = eigenPodManager.getPod(podOwner);

        // bytes32 validatorIndexBytes = bytes32(uint256(validatorIndex0));
        bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);
        newPod.verifyCorrectWithdrawalCredentials(validatorIndex0, proofs, validatorContainerFields);

        cheats.expectRevert(bytes("EigenPod.verifyCorrectWithdrawalCredentials: Validator not inactive"));
        newPod.verifyCorrectWithdrawalCredentials(validatorIndex0, proofs, validatorContainerFields);
    }

    function testWithdrawalProofs() public {
                // bytes32[] memory withdrawalFields;

                //getting proof for withdrawal from beacon chain
                (
                    beaconStateRoot, 
                    executionPayloadHeaderRoot, 
                    blockNumberRoot,
                    executionPayloadHeaderProof,
                    blockNumberProof, 
                    withdrawalMerkleProof,
                    withdrawalContainerFields
                ) = getWithdrawalProofsWithBlockNumber();
                
                Relayer relay = new Relayer();

                BeaconChainProofs.WithdrawalAndBlockNumberProof memory proof = BeaconChainProofs.WithdrawalAndBlockNumberProof(
                                                                            uint16(0), 
                                                                            executionPayloadHeaderRoot, 
                                                                            abi.encodePacked(executionPayloadHeaderProof),
                                                                            uint8(0),
                                                                            abi.encodePacked(withdrawalMerkleProof),
                                                                            abi.encodePacked(blockNumberProof)
                                                                            );
                relay.verifyWithdrawalFieldsAndBlockNumber(
                    beaconStateRoot, 
                    proof, 
                    blockNumberRoot, 
                    withdrawalContainerFields
                );

    }

    function getBeaconChainETHShares(address staker) internal view returns(uint256) {
        return investmentManager.investorStratShares(staker, investmentManager.beaconChainETHStrategy());
    }

    // TEST CASES:

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
    //                     pod owner balance should increaase by AMOUNT - REQUIRED_BALANCE_GWEI
    //                     validator status should be marked as WITHDRAWN

    function testSufficientFullWithdrawal() public {
        uint64 withdrawalAmountGwei = 31400000000;
        IEigenPod pod = testDeployAndVerifyNewEigenPod();

        // withdrawal amount must be sufficient
        cheats.assume(withdrawalAmountGwei >= pod.REQUIRED_BALANCE_GWEI());

        // uint256 paymentsLengthBefore = eigenPodPaymentEscrow.userPaymentsLength(pod.podOwner());
        cheats.deal(address(pod), address(pod).balance + withdrawalAmountGwei * GWEI_TO_WEI);

        // prove sufficient full withdrawal
        _proveFullWithdrawal(pod);

        assertTrue(pod.restakedExecutionLayerGwei() == pod.REQUIRED_BALANCE_GWEI(), "restakedExecutionLayerGwei not set correctly");
        // assertEq(paymentsLengthBefore + 1, eigenPodPaymentEscrow.userPaymentsLength(pod.podOwner()), "payment not added to escrow");
        // assertTrue(_getLatestPaymentAmount(pod.podOwner()) == (withdrawalAmountGwei - pod.REQUIRED_BALANCE_GWEI()) * uint256(GWEI_TO_WEI), "pod owner balance not increased correctly");
        assertTrue(pod.validatorStatus(validatorIndex0) == IEigenPod.VALIDATOR_STATUS.WITHDRAWN, "validator status not set correctly");
    }

    // 5. Prove overcommitted balance
    // Setup: Run (3). 
    // Test: Watcher proves an overcommitted balance for validator from (3).
    // Expected Behaviour: beaconChainETH shares should decrement by REQUIRED_BALANCE_WEI
    //                     validator status should be marked as OVERCOMMITTED

    function testProveOverCommittedBalance(IEigenPod pod, uint40 validatorIndex) internal {
        //IEigenPod pod = testDeployAndVerifyNewEigenPod(signature, depositDataRoot);
        // get beaconChainETH shares
        uint256 beaconChainETHBefore = getBeaconChainETHShares(pod.podOwner());

        // prove overcommitted balance
        _proveOvercommittedStake(pod, validatorIndex);

        assertTrue(beaconChainETHBefore - getBeaconChainETHShares(pod.podOwner()) == pod.REQUIRED_BALANCE_WEI(), "BeaconChainETHShares not updated");
        assertTrue(pod.validatorStatus(validatorIndex) == IEigenPod.VALIDATOR_STATUS.OVERCOMMITTED, "validator status not set correctly");
    }
    
    // 6. Insufficient full withdrawal for active validator
    // Setup: Run (3).
    // Test: Credit the pod balance with AMOUNT (< REQUIRED_BALANCE_GWEI) gwei and then owner submit 
    //       full withdrawal proof for validator from (3) whose balance is overcommitted but has not been marked as such.    
    // Expected Behaviour: beaconChainETH shares should decrement by (REQUIRED_BALANCE_WEI - AMOUNT)
    //                     restakedExecutionLayerBalanceGwei should be AMOUNT
    //                     instantlyWithdrawableBalanceGwei should be 0
    //                     validator status should be marked as OVERCOMMITTED
    // This test tests a "small" withdrawal amount - this affects the behavior in how penalties are paid.
    function testSmallInsufficientFullWithdrawalForActiveValidator() public {
        uint64 withdrawalAmountGwei = 1e9;
        bool isLargeWithdrawal = false;
        IEigenPod pod = testDeployAndVerifyNewEigenPod();

        // the validator must be active, not proven overcommitted
        require(pod.validatorStatus(validatorIndex0) == IEigenPod.VALIDATOR_STATUS.ACTIVE, "Validator must be active");

        // get beaconChainETH shares
        uint256 beaconChainETHBefore = getBeaconChainETHShares(pod.podOwner());
        uint256 podOwnerBalanceBefore = pod.podOwner().balance;

        cheats.deal(address(pod), address(pod).balance + withdrawalAmountGwei * GWEI_TO_WEI);

        // prove insufficient full withdrawal
        _proveInsufficientFullWithdrawal(pod, isLargeWithdrawal);

        uint256 beaconChainETHAfter = getBeaconChainETHShares(pod.podOwner());
        emit log_named_uint("withdrawalAmountGwei", withdrawalAmountGwei);
        emit log_named_uint("beaconChainETHBefore", beaconChainETHBefore);
        emit log_named_uint("beaconChainETHAfter", beaconChainETHAfter);
        emit log_named_uint("pod.REQUIRED_BALANCE_GWEI()", pod.REQUIRED_BALANCE_GWEI());

        uint256 expectedSharePenalty = (uint256(pod.REQUIRED_BALANCE_GWEI()) - uint256(withdrawalAmountGwei)) * 1e9;

        emit log_named_uint("expectedSharePenalty", expectedSharePenalty);

        assertTrue((beaconChainETHBefore - beaconChainETHAfter) == expectedSharePenalty,
            "beaconChainETHShares not updated correctly");
        assertTrue(pod.restakedExecutionLayerGwei() == withdrawalAmountGwei, "restakedExecutionLayerGwei is not 0");
        assertTrue(pod.podOwner().balance == podOwnerBalanceBefore, "pod owner balance has changed");
        assertTrue(pod.validatorStatus(validatorIndex0) == IEigenPod.VALIDATOR_STATUS.WITHDRAWN, "validator status not updated correctly");
    }

    // This test tests a "large" withdrawal amount - this affects the behavior in how penalties are paid.
    function testLargeInsufficientFullWithdrawalForActiveValidator() public {
        uint64 withdrawalAmountGwei = 31000000000;
        bool isLargeWithdrawal = true;
        IEigenPod pod = testDeployAndVerifyNewEigenPod();

        emit log_uint(pod.restakedExecutionLayerGwei());

        // the validator must be active, not proven overcommitted
        require(pod.validatorStatus(validatorIndex0) == IEigenPod.VALIDATOR_STATUS.ACTIVE, "Validator must be active");

        // get beaconChainETH shares
        uint256 beaconChainETHBefore = getBeaconChainETHShares(pod.podOwner());
        uint256 podOwnerBalanceBefore = pod.podOwner().balance;

        cheats.deal(address(pod), address(pod).balance + withdrawalAmountGwei * GWEI_TO_WEI);

        // prove insufficient full withdrawal
        _proveInsufficientFullWithdrawal(pod, isLargeWithdrawal);

        uint256 expectedSharePenalty = (uint256(pod.REQUIRED_BALANCE_GWEI()) - uint256(withdrawalAmountGwei)) * 1e9;

        assertTrue(beaconChainETHBefore - getBeaconChainETHShares(pod.podOwner()) == expectedSharePenalty, "beaconChainETHShares not updated");

        assertTrue(pod.podOwner().balance == podOwnerBalanceBefore, "pod owner balance has changed");
        assertTrue(pod.validatorStatus(validatorIndex0) == IEigenPod.VALIDATOR_STATUS.WITHDRAWN, "validator status not updated correctly");
    }

    // 7. Pay off penalties with sufficient full withdrawal
    // Test: Run (5). Then prove a sufficient withdrawal.
    // Expected Behaviour: restakedExecutionLayerBalanceGwei should be withdrawalAmountGwei
    //                     pod owner balance should increase by AMOUNT - REQUIRED_BALANCE_GWEI
    //                     validator status should be marked as WITHDRWAN

    function testPayOffPenaltiesWithSufficientWithdrawal() public {
        uint64 withdrawalAmountGwei = 31400000000;
        IEigenPod pod = testDeployAndVerifyNewEigenPod();

        require(pod.restakedExecutionLayerGwei() == 0);

        testProveOverCommittedBalance(pod, validatorIndex0);

        uint256 podOwnerBalanceBefore = pod.podOwner().balance;

        cheats.deal(address(pod), address(pod).balance + withdrawalAmountGwei * GWEI_TO_WEI);

        // prove sufficient full withdrawal
        _proveFullWithdrawal(pod);

        assertEq(pod.restakedExecutionLayerGwei(), withdrawalAmountGwei);
        assertEq(pod.podOwner().balance - podOwnerBalanceBefore, (withdrawalAmountGwei - pod.REQUIRED_BALANCE_GWEI()) * uint256(GWEI_TO_WEI));
        assertTrue(pod.validatorStatus(validatorIndex0) == IEigenPod.VALIDATOR_STATUS.WITHDRAWN);
    }

    function testPayOffMultiplePenaltiesWithSufficientWithdrawal() public {
        uint64 withdrawalAmountGwei = 31400000000;
        IEigenPod pod = testDeployAndVerifyNewEigenPod();
        _testVerifyNewValidator(pod, validatorIndex1);
        
        require(pod.restakedExecutionLayerGwei() == 0);
        // withdrawal amount must be sufficient
        cheats.assume(withdrawalAmountGwei >= pod.REQUIRED_BALANCE_GWEI() && withdrawalAmountGwei <= 33 ether);

        //first we prove overcommitted balances, incurring penalites
        testProveOverCommittedBalance(pod, validatorIndex0);
        testProveOverCommittedBalance(pod, validatorIndex1);

        cheats.deal(address(pod), address(pod).balance + withdrawalAmountGwei * GWEI_TO_WEI);

        // prove sufficient full withdrawal for validatorIndex0, to cover the penalites
        _proveFullWithdrawal(pod);

        assertEq(pod.restakedExecutionLayerGwei(), withdrawalAmountGwei);
        assertTrue(pod.validatorStatus(validatorIndex0) == IEigenPod.VALIDATOR_STATUS.WITHDRAWN);
    }

    // 11. Make partial withdrawal claim
    // Test: Credit balance with PARTIAL_AMOUNT_GWEI gwei and record a balance snapshot with an expire block far in the future
    // Expected Behaviour: Should append a pending a partial withdrawal claim for 
    //                     (pod.balance - restakedExecutionLayerGwei) amount 
    //                     at block.number to the end of the partial withdrawal list

    function testMakePartialWithdrawalClaim(uint64 partialWithdrawalAmountGwei) public returns(IEigenPod,  IEigenPod.PartialWithdrawalClaim memory){
        IEigenPod pod = testDeployAndVerifyNewEigenPod();

        uint64 restakedExectionLayerGweiBefore = pod.restakedExecutionLayerGwei();
        uint256 lengthBefore = pod.getPartialWithdrawalClaimsLength();
        cheats.assume(partialWithdrawalAmountGwei > restakedExectionLayerGweiBefore);
        cheats.deal(address(pod), address(pod).balance + partialWithdrawalAmountGwei * GWEI_TO_WEI);

        cheats.prank(pod.podOwner());
        pod.recordPartialWithdrawalClaim(uint32(block.number + 100));

        IEigenPod.PartialWithdrawalClaim memory claim = pod.getPartialWithdrawalClaim(pod.getPartialWithdrawalClaimsLength() - 1);

        require(claim.status == IEigenPod.PARTIAL_WITHDRAWAL_CLAIM_STATUS.PENDING, "status not set to pending");
        require(claim.partialWithdrawalAmountGwei == uint64(address(pod).balance / GWEI_TO_WEI) - restakedExectionLayerGweiBefore, "partialWithdrawalAmount not correct");
        require(pod.getPartialWithdrawalClaimsLength() == lengthBefore + 1, "partialWithdrawalClaim not added");
        return (pod, claim);

    }

    // 16. Test happy partial withdrawal
    // Setup: Run (11). 
    // Test: PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS pass. Pod owner attempts to redeem partial withdrawal
    // Expected Behaviour: pod.balance should be decremented by PARTIAL_AMOUNT_GWEI gwei
    //                     podOwner balance should be incremented by PARTIAL_AMOUNT_GWEI gwei
    //                     partial withdrawal should be marked as redeemed
    function testRedeemPartialWithdrawalClaim(uint64 partialWithdrawalAmountGwei) public {
        (IEigenPod pod, IEigenPod.PartialWithdrawalClaim memory claim) = testMakePartialWithdrawalClaim(partialWithdrawalAmountGwei);
        
        uint256 recipientBalanceBefore = podOwner.balance;
        uint256 podBalanceBefore = address(pod).balance;

        cheats.prank(podOwner);
        cheats.roll(claim.fraudproofPeriodEndBlockNumber + 1);
        pod.redeemLatestPartialWithdrawal(podOwner);

        // claim payment
        cheats.roll(block.number + eigenPodPaymentEscrow.withdrawalDelayBlocks());
        eigenPodPaymentEscrow.claimPayments(podOwner, 1);

        assertEq(podOwner.balance - recipientBalanceBefore, (uint256(claim.partialWithdrawalAmountGwei) * uint256(1e9))); 
        assertEq(podBalanceBefore - address(pod).balance, (uint256(claim.partialWithdrawalAmountGwei) * uint256(1e9))); 
    }

    // 12. Expired partial withdrawal claim
    // Setup: Credit balance with PARTIAL_AMOUNT gwei
    // Test: Record a balance snapshot with an expire block in the past
    // Expected Behaviour: Reverts due to expiry

    function testExpiredPartialWithdrawalClaim(uint64 partialWithdrawalAmountGwei, uint32 expireBlockNumber) public {
        IEigenPod pod = testDeployAndVerifyNewEigenPod();

        uint64 restakedExectionLayerGweiBefore = pod.restakedExecutionLayerGwei();
        cheats.assume(partialWithdrawalAmountGwei >= restakedExectionLayerGweiBefore);
        cheats.deal(address(pod), address(pod).balance + partialWithdrawalAmountGwei * GWEI_TO_WEI);

        cheats.prank(pod.podOwner());
        cheats.assume(expireBlockNumber < uint32(block.number));
        cheats.expectRevert(bytes("EigenPod.recordBalanceSnapshot: recordPartialWithdrawalClaim tx mined too late"));
        pod.recordPartialWithdrawalClaim(expireBlockNumber);
    }

    // 14. Premature partial withdrawal claim redemption
    // Setup: Run (11).
    // Test: Pod owner attempts to redeem partial withdrawals after a duration of blocks less than PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS
    // Expected Behaviour: Reverts because fraud proof period has not passed
    function testPrematurePartialWithdrawalClaim(uint64 partialWithdrawalAmountGwei, address recipient) public fuzzedAddress(recipient){
        (IEigenPod pod,) = testMakePartialWithdrawalClaim(partialWithdrawalAmountGwei);
        cheats.prank(podOwner);
        cheats.expectRevert(bytes("EigenPod.redeemLatestPartialWithdrawal: can only redeem partial withdrawals after fraudproof period"));
        pod.redeemLatestPartialWithdrawal(recipient);
    }

    // 15. Fraudulent partial withdrawal
    // Setup: Credit balance with AMOUNT (>= REQUIRED_BALANCE_GWEI). Run (11).
    // Test: Watcher proves withdrawal of AMOUNT before the block in which (11) occured.
    // Expected Behaviour: Partial withdrawal should be marked as failed.
    function testFraudulentPartialWithdrawal(uint64 partialWithdrawalAmountGwei) public returns(IEigenPod){
        //cheats.roll(block.number + 100);
        (IEigenPod pod, ) = testMakePartialWithdrawalClaim(partialWithdrawalAmountGwei);
        
        uint64 withdrawalAmountGwei = 31400000000;
        // withdrawal amount must be sufficient
        cheats.assume(withdrawalAmountGwei >= pod.REQUIRED_BALANCE_GWEI() && withdrawalAmountGwei <= 33 ether);
        cheats.deal(address(pod), address(pod).balance + withdrawalAmountGwei * GWEI_TO_WEI);
        // prove sufficient full withdrawal
        _proveFullWithdrawal(pod);

        //ensure that partial withdrawal claim is failed because latest claim's creation blocknumber is after most recent full withdrawal
        IEigenPod.PartialWithdrawalClaim memory currentClaim = pod.getPartialWithdrawalClaim(pod.getPartialWithdrawalClaimsLength() - 1);
        require(currentClaim.status == IEigenPod.PARTIAL_WITHDRAWAL_CLAIM_STATUS.FAILED, "status not set correctly");
        return pod;
    }


    // 15. Redeem fraudulent partial withdrawal
    // Setup: Run (14).
    // Test: Pod owner attempts to redeem partial withdrawal
    // Expected Behaviour: Reverts because withdrawal is not pending
    function testRedeemFraudulentPartialWithdrawal(uint64 partialWithdrawalAmountGwei) public {
        IEigenPod pod = testFraudulentPartialWithdrawal(partialWithdrawalAmountGwei);

        cheats.prank(podOwner);
        cheats.expectRevert(bytes("EigenPod.redeemLatestPartialWithdrawal: partial withdrawal either redeemed or failed making it ineligible for redemption"));
        pod.redeemLatestPartialWithdrawal(podOwner);
    }

    // 17. Double partial withdrawal
    // Setup: Run (11). 
    // Test: before PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS have passed, run (11).
    // Expected Behaviour: Revert with partial withdrawal already exists
    function testDoublePartialWithdrawal(uint64 partialWithdrawalAmountGwei) public {
        (IEigenPod pod,  ) = testMakePartialWithdrawalClaim(partialWithdrawalAmountGwei);
        cheats.prank(pod.podOwner());
        cheats.expectRevert(bytes("EigenPod.recordPartialWithdrawalClaim: cannot make a new claim until previous claim is not pending"));
        pod.recordPartialWithdrawalClaim(uint32(block.number + 100));
        
    }

    // 20. Pay penalties from partial withdrawal and then roll over balance
    // Setup: Run (18).
    // Test: Run enough full withdrawals until all penalties are paid. Attempt to roll over toRollAmountGwei.
    // Expected Behaviour: Math is more complicated here, but keep track of rollable balance and make sure it
    //                     always accounts for the parital withdrawal

    function testEigenPodsQueuedWithdrawal(address operator) public fuzzedAddress(operator){
        cheats.assume(operator != podOwner);
        //make initial deposit
        testDeployAndVerifyNewEigenPod();

        //*************************DELEGATION+REGISTRATION OF OPERATOR******************************//
        _testDelegation(operator, podOwner);


        cheats.startPrank(operator);
        investmentManager.slasher().optIntoSlashing(address(generalServiceManager1));
        cheats.stopPrank();


        generalReg1.registerOperator(operator, uint32(block.timestamp) + 3 days);
        //*********************************************************************************************//

        {
                IEigenPod newPod;
                newPod = eigenPodManager.getPod(podOwner);
                //adding balance to pod to simulate a withdrawal
                cheats.deal(address(newPod), stakeAmount);
                //getting proof for withdrawal from beacon chain
               _proveFullWithdrawal(newPod);
        }
        
        IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
        IERC20[] memory tokensArray = new IERC20[](1);
        uint256[] memory shareAmounts = new uint256[](1);
        uint256[] memory strategyIndexes = new uint256[](1);
        IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce =
            IInvestmentManager.WithdrawerAndNonce({withdrawer: podOwner, nonce: 0});
        bool undelegateIfPossible = false;
        {
            strategyArray[0] = investmentManager.beaconChainETHStrategy();
            shareAmounts[0] = REQUIRED_BALANCE_WEI;
            strategyIndexes[0] = 0;
        }


        uint256 podOwnerSharesBefore = investmentManager.investorStratShares(podOwner, investmentManager.beaconChainETHStrategy());
        

        cheats.warp(uint32(block.timestamp) + 1 days);
        cheats.roll(uint32(block.timestamp) + 1 days);

        _testQueueWithdrawal(podOwner, strategyIndexes, strategyArray, shareAmounts, undelegateIfPossible);
        uint32 queuedWithdrawalStartBlock = uint32(block.number);

        //*************************DELEGATION/Stake Update STUFF******************************//
        //now withdrawal block time is before deregistration
        cheats.warp(uint32(block.timestamp) + 2 days);
        cheats.roll(uint32(block.timestamp) + 2 days);
        
        generalReg1.deregisterOperator(operator);

        //warp past the serve until time, which is 3 days from the beginning.  THis puts us at 4 days past that point
        cheats.warp(uint32(block.timestamp) + 4 days);
        cheats.roll(uint32(block.timestamp) + 4 days);
        //*************************************************************************//

        uint256 podOwnerSharesAfter = investmentManager.investorStratShares(podOwner, investmentManager.beaconChainETHStrategy());

        require(podOwnerSharesBefore - podOwnerSharesAfter == REQUIRED_BALANCE_WEI, "delegation shares not updated correctly");

        address delegatedAddress = delegation.delegatedTo(podOwner);
        IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal = IInvestmentManager.QueuedWithdrawal({
            strategies: strategyArray,
            shares: shareAmounts,
            depositor: podOwner,
            withdrawerAndNonce: withdrawerAndNonce,
            withdrawalStartBlock: queuedWithdrawalStartBlock,
            delegatedAddress: delegatedAddress
        });

        uint256 podOwnerBalanceBefore = podOwner.balance;
        uint256 middlewareTimesIndex = 1;
        bool receiveAsTokens = true;
        cheats.startPrank(podOwner);

        investmentManager.completeQueuedWithdrawal(queuedWithdrawal, tokensArray, middlewareTimesIndex, receiveAsTokens);

        cheats.stopPrank();

        // claim payment
        cheats.roll(block.number + eigenPodPaymentEscrow.withdrawalDelayBlocks());
        eigenPodPaymentEscrow.claimPayments(podOwner, 1);

        require(podOwner.balance - podOwnerBalanceBefore == shareAmounts[0], "podOwner balance not updated correcty");
    }

    function testDeployingEigenPodRevertsWhenPaused() external {
        // pause the contract
        cheats.startPrank(eigenPodManager.pauserRegistry().pauser());
        eigenPodManager.pause(2 ** PAUSED_NEW_EIGENPODS);
        cheats.stopPrank();

        cheats.startPrank(podOwner);
        cheats.expectRevert(bytes("Pausable: index is paused"));
        eigenPodManager.stake{value: stakeAmount}(pubkey, signature, depositDataRoot);
        cheats.stopPrank();
    }

    function testWithdrawRestakedBeaconChainETHRevertsWhenPaused() external {
        // pause the contract
        cheats.startPrank(eigenPodManager.pauserRegistry().pauser());
        eigenPodManager.pause(2 ** PAUSED_WITHDRAW_RESTAKED_ETH);
        cheats.stopPrank();

        address recipient = address(this);
        uint256 amount = 1e18;
        cheats.startPrank(address(eigenPodManager.investmentManager()));
        cheats.expectRevert(bytes("Pausable: index is paused"));
        eigenPodManager.withdrawRestakedBeaconChainETH(podOwner, recipient, amount);
        cheats.stopPrank();
    }

    function testVerifyCorrectWithdrawalCredentialsRevertsWhenPaused() external {
        uint40 validatorIndex = validatorIndex1;
        IEigenPod pod = testDeployAndVerifyNewEigenPod();
        _testVerifyNewValidator(pod, validatorIndex);

        (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) =
            getInitialDepositProof(validatorIndex);
        bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);

        // pause the contract
        cheats.startPrank(eigenPodManager.pauserRegistry().pauser());
        eigenPodManager.pause(2 ** PAUSED_EIGENPODS_VERIFY_CREDENTIALS);
        cheats.stopPrank();

        cheats.expectRevert(bytes("EigenPod.onlyWhenNotPaused: index is paused in EigenPodManager"));
        pod.verifyCorrectWithdrawalCredentials(validatorIndex, proofs, validatorContainerFields);
    }

    function testVerifyOvercommittedStakeRevertsWhenPaused() external {
        uint40 validatorIndex = validatorIndex0;
        IEigenPod pod = testDeployAndVerifyNewEigenPod();

        (
            beaconStateRoot, 
            beaconStateMerkleProofForValidators, 
            validatorContainerFields, 
            validatorMerkleProof, 
            validatorTreeRoot, 
            validatorRoot
        ) = getSlashedDepositProof(validatorIndex);

        beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);
        
        // bytes32 validatorIndexBytes = bytes32(uint256(validatorIndex));
        bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);

        // pause the contract
        cheats.startPrank(eigenPodManager.pauserRegistry().pauser());
        eigenPodManager.pause(2 ** PAUSED_EIGENPODS_VERIFY_OVERCOMMITTED);
        cheats.stopPrank();

        cheats.expectRevert(bytes("EigenPod.onlyWhenNotPaused: index is paused in EigenPodManager"));
        pod.verifyOvercommittedStake(validatorIndex, proofs, validatorContainerFields, 0);
    }

    function testVerifyBeaconChainFullWithdrawalRevertsWhenPaused() external {
        // pause the contract
        cheats.startPrank(eigenPodManager.pauserRegistry().pauser());
        eigenPodManager.pause(2 ** PAUSED_EIGENPODS_VERIFY_WITHDRAWAL);
        cheats.stopPrank();

        IEigenPod pod = testDeployAndVerifyNewEigenPod();

        (
            beaconStateRoot, 
            executionPayloadHeaderRoot, 
            blockNumberRoot,
            executionPayloadHeaderProof,
            blockNumberProof, 
            withdrawalMerkleProof,
            withdrawalContainerFields
        ) = getWithdrawalProofsWithBlockNumber();

        beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);
        BeaconChainProofs.WithdrawalAndBlockNumberProof memory proof = BeaconChainProofs.WithdrawalAndBlockNumberProof(
                                                                    uint16(0), 
                                                                    executionPayloadHeaderRoot, 
                                                                    abi.encodePacked(executionPayloadHeaderProof),
                                                                    uint8(0),
                                                                    abi.encodePacked(withdrawalMerkleProof),
                                                                    abi.encodePacked(blockNumberProof)
                                                                    );

        cheats.expectRevert(bytes("EigenPod.onlyWhenNotPaused: index is paused in EigenPodManager"));
        pod.verifyBeaconChainFullWithdrawal(proof, blockNumberRoot, withdrawalContainerFields,  0);
    }

    // simply tries to register 'sender' as a delegate, setting their 'DelegationTerms' contract in EigenLayerDelegation to 'dt'
    // verifies that the storage of EigenLayerDelegation contract is updated appropriately
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

    function _testDeployAndVerifyNewEigenPod(address _podOwner, bytes memory _signature, bytes32 _depositDataRoot, bool /*isContract*/, uint40 validatorIndex)
        internal returns (IEigenPod)
    {
        (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) =
            getInitialDepositProof(validatorIndex);

        cheats.startPrank(_podOwner);
        eigenPodManager.stake{value: stakeAmount}(pubkey, _signature, _depositDataRoot);
        cheats.stopPrank();

        beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);

        IEigenPod newPod;

        newPod = eigenPodManager.getPod(_podOwner);

        bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);

        newPod.verifyCorrectWithdrawalCredentials(validatorIndex, proofs, validatorContainerFields);

        IInvestmentStrategy beaconChainETHStrategy = investmentManager.beaconChainETHStrategy();

        uint256 beaconChainETHShares = investmentManager.investorStratShares(_podOwner, beaconChainETHStrategy);
        require(beaconChainETHShares == REQUIRED_BALANCE_WEI, "investmentManager shares not updated correctly");
        return newPod;
    }

    function _testVerifyNewValidator(IEigenPod pod, uint40 validatorIndex) internal {
        (beaconStateRoot, beaconStateMerkleProofForValidators, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) =
            getInitialDepositProof(validatorIndex);
        bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);

        pod.verifyCorrectWithdrawalCredentials(validatorIndex, proofs, validatorContainerFields);
    }

    function _proveFullWithdrawal(IEigenPod pod) internal {
        (
            beaconStateRoot, 
            executionPayloadHeaderRoot, 
            blockNumberRoot,
            executionPayloadHeaderProof,
            blockNumberProof, 
            withdrawalMerkleProof,
            withdrawalContainerFields
        ) = getWithdrawalProofsWithBlockNumber();

        beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);
        BeaconChainProofs.WithdrawalAndBlockNumberProof memory proof = BeaconChainProofs.WithdrawalAndBlockNumberProof(
                                                                    uint16(0), 
                                                                    executionPayloadHeaderRoot, 
                                                                    abi.encodePacked(executionPayloadHeaderProof),
                                                                    uint8(0),
                                                                    abi.encodePacked(withdrawalMerkleProof),
                                                                    abi.encodePacked(blockNumberProof)
                                                                    );

        pod.verifyBeaconChainFullWithdrawal(proof, blockNumberRoot, withdrawalContainerFields,  0);
    }

    function _proveInsufficientFullWithdrawal(IEigenPod pod, bool isLargeWithdrawal) internal {

        if(!isLargeWithdrawal){
            (
                beaconStateRoot, 
                executionPayloadHeaderRoot, 
                blockNumberRoot,
                executionPayloadHeaderProof,
                blockNumberProof, 
                withdrawalMerkleProof,
                withdrawalContainerFields
            ) = getSmallInsufficientFullWithdrawalProof();

            beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);
            BeaconChainProofs.WithdrawalAndBlockNumberProof memory proof = BeaconChainProofs.WithdrawalAndBlockNumberProof(
                                                                        uint16(0), 
                                                                        executionPayloadHeaderRoot, 
                                                                        abi.encodePacked(executionPayloadHeaderProof),
                                                                        uint8(0),
                                                                        abi.encodePacked(withdrawalMerkleProof),
                                                                        abi.encodePacked(blockNumberProof)
                                                                        );
            pod.verifyBeaconChainFullWithdrawal(proof, blockNumberRoot, withdrawalContainerFields,  0);
        } else {
            (
                beaconStateRoot, 
                executionPayloadHeaderRoot, 
                blockNumberRoot,
                executionPayloadHeaderProof,
                blockNumberProof, 
                withdrawalMerkleProof,
                withdrawalContainerFields
            ) = getLargeInsufficientFullWithdrawalProof();

            beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);
            BeaconChainProofs.WithdrawalAndBlockNumberProof memory proof = BeaconChainProofs.WithdrawalAndBlockNumberProof(
                                                                        uint16(0), 
                                                                        executionPayloadHeaderRoot, 
                                                                        abi.encodePacked(executionPayloadHeaderProof),
                                                                        uint8(0),
                                                                        abi.encodePacked(withdrawalMerkleProof),
                                                                        abi.encodePacked(blockNumberProof)
                                                                        );
            pod.verifyBeaconChainFullWithdrawal(proof, blockNumberRoot, withdrawalContainerFields,  0);
        }
    }

    function _proveOvercommittedStake(IEigenPod pod, uint40 validatorIndex) internal {
        (
            beaconStateRoot, 
            beaconStateMerkleProofForValidators, 
            validatorContainerFields, 
            validatorMerkleProof, 
            validatorTreeRoot, 
            validatorRoot
        ) = getSlashedDepositProof(validatorIndex);

        beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);
        
        // bytes32 validatorIndexBytes = bytes32(uint256(validatorIndex));
        bytes memory proofs = abi.encodePacked(validatorMerkleProof, beaconStateMerkleProofForValidators);
        pod.verifyOvercommittedStake(validatorIndex, proofs, validatorContainerFields, 0);
    }

    function _testQueueWithdrawal(
        address depositor,
        uint256[] memory strategyIndexes,
        IInvestmentStrategy[] memory strategyArray,
        uint256[] memory shareAmounts,
        bool undelegateIfPossible
    )
        internal
        returns (bytes32)
    {
        cheats.startPrank(depositor);

        //make a call with depositor aka podOwner also as withdrawer.
        bytes32 withdrawalRoot = investmentManager.queueWithdrawal(
            strategyIndexes,
            strategyArray,
            shareAmounts,
            depositor,
            // TODO: make this an input
            undelegateIfPossible
        );

        cheats.stopPrank();
        return withdrawalRoot;
    }

    function _getLatestPaymentAmount(address recipient) internal view returns (uint256) {
        return eigenPodPaymentEscrow.userPaymentByIndex(recipient, eigenPodPaymentEscrow.userPaymentsLength(recipient) - 1).amount;
    }

 }


 contract Relayer is Test {
    function verifyWithdrawalFieldsAndBlockNumber(
        bytes32 beaconStateRoot,
        BeaconChainProofs.WithdrawalAndBlockNumberProof calldata proof,
        bytes32 blockNumberRoot,
        bytes32[] calldata withdrawalFields
    ) public view {
        BeaconChainProofs.verifyWithdrawalFieldsAndBlockNumber(beaconStateRoot, proof, blockNumberRoot, withdrawalFields);
    }

    function verifySlotAndWithdrawalFields(
        bytes32 beaconStateRoot,
        BeaconChainProofs.WithdrawalProofs calldata proofs,
        bytes32[] calldata withdrawalFields,
        bytes32[] calldata validatorFields
    ) public view {
        BeaconChainProofs.verifySlotAndWithdrawalFields(beaconStateRoot, proofs, withdrawalFields, validatorFields);
    }
 }