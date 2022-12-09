// //SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

 import "../contracts/interfaces/IEigenPod.sol";
 import "./utils/BeaconChainUtils.sol";
import "./EigenLayrDeployer.t.sol";
 import "./mocks/MiddlewareRegistryMock.sol";
import "./mocks/ServiceManagerMock.sol";

contract EigenPodTests is BeaconChainProofUtils, DSTest {
    using BytesLib for bytes;

    bytes pubkey = hex"88347ed1c492eedc97fc8c506a35d44d81f27a0c7a1c661b35913cfd15256c0cccbd34a83341f505c7de2983292f2cab";
    uint64 validatorIndex = 0;
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
    IEigenPod public pod;
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
        pod = new EigenPod(
                ethPOSDeposit, 
                PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD, 
                REQUIRED_BALANCE_WEI,
                MIN_FULL_WITHDRAWAL_AMOUNT_GWEI
        );

        eigenPodBeacon = new UpgradeableBeacon(address(pod));

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
        bytes memory proofs = abi.encodePacked(validatorTreeRoot, beaconStateMerkleProofForValidators, validatorRoot, validatorIndexBytes, validatorMerkleProof);
        eigenPod.verifyOvercommitedStake(proofs, validatorContainerFields, 0);
        
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

        bytes32 validatorIndexBytes = bytes32(uint256(validatorIndex));
        bytes memory proofs = abi.encodePacked(validatorTreeRoot, beaconStateMerkleProofForValidators, validatorRoot, validatorIndexBytes, validatorMerkleProof);
        cheats.expectRevert(bytes("EigenPod.verifyValidatorFields: Invalid validator fields"));
        newPod.verifyCorrectWithdrawalCredentials(proofs, validatorContainerFields);
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
        bytes memory proofs = abi.encodePacked(validatorTreeRoot, beaconStateMerkleProofForValidators, validatorRoot, validatorIndexBytes, validatorMerkleProof);
        newPod.verifyCorrectWithdrawalCredentials(proofs, validatorContainerFields);

        cheats.expectRevert(bytes("EigenPod.verifyCorrectWithdrawalCredentials: Validator not inactive"));
        newPod.verifyCorrectWithdrawalCredentials(proofs, validatorContainerFields);
    }

    function testVerifyWithdrawalProofs() public {
                bytes32[] memory withdrawalFields;

                //getting proof for withdrawal from beacon chain
                (
                    withdrawalFields, 
                    beaconStateRoot, 
                    beaconStateMerkleProofForExecutionPayloadHeader, 
                    executionPayloadHeaderRoot, 
                    executionPayloadHeaderProofForWithdrawalProof, 
                    withdrawalTreeRoot,
                    withdrawalMerkleProof,
                    withdrawalRoot
                ) = getWithdrawalProof();



                beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);
                bytes memory proofs = abi.encodePacked(
                                        executionPayloadHeaderRoot, 
                                        beaconStateMerkleProofForExecutionPayloadHeader, 
                                        withdrawalTreeRoot, 
                                        executionPayloadHeaderProofForWithdrawalProof,
                                        withdrawalRoot,
                                        bytes32(uint256(0)), 
                                        withdrawalMerkleProof
                                    );

                Relayer relay = new Relayer();
                relay.verifyWithdrawalProofsHelp(
                    beaconStateRoot,
                    proofs,
                    withdrawalFields
                );
        
    }

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
        bytes memory proofs = abi.encodePacked(validatorTreeRoot, beaconStateMerkleProofForValidators, validatorRoot, validatorIndexBytes, validatorMerkleProof);
        newPod.verifyCorrectWithdrawalCredentials(proofs, validatorContainerFields);

        IInvestmentStrategy beaconChainETHStrategy = investmentManager.beaconChainETHStrategy();

        uint256 beaconChainETHShares = investmentManager.investorStratShares(_podOwner, beaconChainETHStrategy);
        require(beaconChainETHShares == REQUIRED_BALANCE_WEI, "investmentManager shares not updated correctly");
    }


    function verifyWithdrawalProofs(
        bytes32 beaconStateRoot, 
        bytes memory proofs, 
        bytes32[] memory withdrawalFields
    ) internal {
        require(withdrawalFields.length == BeaconChainProofs.NUM_WITHDRAWAL_FIELDS, "incorrect executionPayloadHeaderFields length");
        uint256 pointer = 0;
        bool valid;

        //check that beacon state root from oracle is present in historical roots
        //TODO: uncomment
        //pointer = verifyBeaconChainRootProof(beaconStateRoot, proofs, pointer);

        
        bytes32 executionPayloadHeaderRoot = proofs.toBytes32(0);
        pointer += 32;
        //verify that execution payload header root is correct against beacon state root
        valid = Merkle.verifyInclusionSha256(
            proofs.slice(pointer, 32 * BeaconChainProofs.BEACON_STATE_FIELD_TREE_HEIGHT), 
            beaconStateRoot, 
            executionPayloadHeaderRoot, 
            BeaconChainProofs.EXECUTION_PAYLOAD_HEADER_INDEX
        );
        require(valid, "Invalid execution payload header proof");

        pointer += 32 * BeaconChainProofs.BEACON_STATE_FIELD_TREE_HEIGHT;
        bytes32 withdrawalsRoot = proofs.toBytes32(pointer);
        pointer +=32;

        //verify that the withdrawals root is correct against the execution payload header root
        valid = Merkle.verifyInclusionSha256(
            proofs.slice(pointer, 32 * BeaconChainProofs.EXECUTION_PAYLOAD_HEADER_FIELD_TREE_HEIGHT), 
            executionPayloadHeaderRoot, 
            withdrawalsRoot, 
            BeaconChainProofs.WITHDRAWALS_ROOT_INDEX
        );
        require(valid, "Invalid withdrawals root proof");

        pointer += 32 * BeaconChainProofs.EXECUTION_PAYLOAD_HEADER_FIELD_TREE_HEIGHT;
        bytes32 individualWithdrawalContainerRoot = proofs.toBytes32(pointer);
        pointer += 32;


        require(individualWithdrawalContainerRoot == Merkle.merkleizeSha256(withdrawalFields), "provided withdrawalFields do not match withdrawalContainerRoot");


        valid = Merkle.verifyInclusionSha256(
            proofs.slice(pointer + 32, 32 * (BeaconChainProofs.WITHDRAWALS_TREE_HEIGHT + 1)),
            withdrawalsRoot,
            individualWithdrawalContainerRoot,
            proofs.toUint256(pointer)
        );

        require(valid, "invalid withdrawal container inclusion proof");
    }
 }


 contract Relayer is Test {
    function verifyWithdrawalProofsHelp(
        bytes32 beaconStateRoot, 
        bytes calldata proofs, 
        bytes32[] calldata withdrawalFields
    ) public {
        BeaconChainProofs.verifyWithdrawalProofs(beaconStateRoot, proofs, withdrawalFields);
    }
 }