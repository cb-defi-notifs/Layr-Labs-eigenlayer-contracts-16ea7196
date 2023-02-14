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
        slotRoot = getSlotRoot();
        blockNumberRoot = getBlockNumberRoot();
        executionPayloadRoot = getExecutionPayloadRoot();

        uint256 validatorIndex = getValidatorIndex(); 

        uint256 withdrawalIndex = getWithdrawalIndex();
        uint256 blockHeaderRootIndex = getBlockHeaderRootIndex();

        blockHeaderProof = getBlockHeaderProof();
        withdrawalProof = getWithdrawalProof();
        slotProof = getSlotProof();
        validatorProof = getValidatorProof();
        executionPayloadProof = getExecutionPayloadProof();
        blockNumberProof = getBlockNumberProof();

        withdrawalFields = getWithdrawalFields();   
        validatorFields = getValidatorFields();


        BeaconChainProofs.WithdrawalProofs memory proofs = BeaconChainProofs.WithdrawalProofs(
            abi.encodePacked(blockHeaderProof),
            abi.encodePacked(withdrawalProof),
            abi.encodePacked(slotProof),
            abi.encodePacked(validatorProof),
            abi.encodePacked(executionPayloadProof),
            abi.encodePacked(blockNumberProof),
            uint16(blockHeaderRootIndex),
            uint8(withdrawalIndex),
            uint8(validatorIndex),
            blockHeaderRoot,
            blockBodyRoot,
            slotRoot,
            blockNumberRoot,
            executionPayloadRoot
        );

        Relayer relay = new Relayer();

        emit log_named_uint("length withdrawal firle", withdrawalFields.length);

        emit log_named_uint("proofs.validatorIndex", proofs.validatorIndex);

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
    function verifySlotAndWithdrawalFields(
        bytes32 beaconStateRoot,
        BeaconChainProofs.WithdrawalProofs calldata proofs,
        bytes32[] calldata withdrawalFields,
        bytes32[] calldata validatorFields
    ) public view {
        BeaconChainProofs.verifySlotAndWithdrawalFields(beaconStateRoot, proofs, withdrawalFields, validatorFields);
    }
 }