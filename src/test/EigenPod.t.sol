// //SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.9;

//  import "../contracts/interfaces/IEigenPod.sol";
//  import "./utils/BeaconChainUtils.sol";
// import "./EigenLayrDeployer.t.sol";
//  import "./mocks/MiddlewareRegistryMock.sol";
// import "./mocks/ServiceManagerMock.sol";
// import "./mocks/BeaconChainETHReceiver.sol";

// contract EigenPodTests is BeaconChainProofUtils, DSTest {
//     using BytesLib for bytes;

//     bytes pubkey = hex"88347ed1c492eedc97fc8c506a35d44d81f27a0c7a1c661b35913cfd15256c0cccbd34a83341f505c7de2983292f2cab";
    
//     //hash tree root of list of validators
//     bytes32 validatorTreeRoot;

//     //hash tree root of individual validator container
//     bytes32 validatorRoot;

//     address podOwner = address(42000094993494);

//     Vm cheats = Vm(HEVM_ADDRESS);
//     EigenLayrDelegation public delegation;
//     InvestmentManager public investmentManager;
//     Slasher public slasher;
//     PauserRegistry public pauserReg;

//     ProxyAdmin public eigenLayrProxyAdmin;
//     IBLSPublicKeyCompendium public blsPkCompendium;
//     IEigenPodManager public eigenPodManager;
//     IEigenPod public pod;
//     IETHPOSDeposit public ethPOSDeposit;
//     IBeacon public eigenPodBeacon;
//     IBeaconChainOracle public beaconChainOracle;
//     MiddlewareRegistryMock public generalReg1;
//     ServiceManagerMock public generalServiceManager1;
//     IBeaconChainETHReceiver public beaconChainETHReceiver;
//     address[] public slashingContracts;
//     address pauser = address(69);
//     address unpauser = address(489);


//     //performs basic deployment before each test
//     function setUp() public {
//         // deploy proxy admin for ability to upgrade proxy contracts
//         eigenLayrProxyAdmin = new ProxyAdmin();

//         // deploy pauser registry
//         pauserReg = new PauserRegistry(pauser, unpauser);

//         blsPkCompendium = new BLSPublicKeyCompendium();

//         /**
//          * First, deploy upgradeable proxy contracts that **will point** to the implementations. Since the implementation contracts are
//          * not yet deployed, we give these proxies an empty contract as the initial implementation, to act as if they have no code.
//          */
//         EmptyContract emptyContract = new EmptyContract();
//         delegation = EigenLayrDelegation(
//             address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
//         );
//         investmentManager = InvestmentManager(
//             address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
//         );
//         slasher = Slasher(
//             address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
//         );

//         beaconChainOracle = new BeaconChainOracleMock();

//         ethPOSDeposit = new ETHPOSDepositMock();
//         pod = new EigenPod(ethPOSDeposit);

//         eigenPodBeacon = new UpgradeableBeacon(address(pod));

//         // this contract is deployed later to keep its address the same (for these tests)
//         eigenPodManager = EigenPodManager(
//             address(new TransparentUpgradeableProxy(address(emptyContract), address(eigenLayrProxyAdmin), ""))
//         );

//         // Second, deploy the *implementation* contracts, using the *proxy contracts* as inputs
//         EigenLayrDelegation delegationImplementation = new EigenLayrDelegation(investmentManager);
//         InvestmentManager investmentManagerImplementation = new InvestmentManager(delegation, eigenPodManager, slasher);
//         Slasher slasherImplementation = new Slasher(investmentManager, delegation);
//         EigenPodManager eigenPodManagerImplementation = new EigenPodManager(ethPOSDeposit, eigenPodBeacon, investmentManager);


//         address initialOwner = address(this);
//         // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
//         eigenLayrProxyAdmin.upgradeAndCall(
//             TransparentUpgradeableProxy(payable(address(delegation))),
//             address(delegationImplementation),
//             abi.encodeWithSelector(EigenLayrDelegation.initialize.selector, pauserReg, initialOwner)
//         );
//         eigenLayrProxyAdmin.upgradeAndCall(
//             TransparentUpgradeableProxy(payable(address(investmentManager))),
//             address(investmentManagerImplementation),
//             abi.encodeWithSelector(InvestmentManager.initialize.selector, pauserReg, initialOwner)
//         );
//         eigenLayrProxyAdmin.upgradeAndCall(
//             TransparentUpgradeableProxy(payable(address(slasher))),
//             address(slasherImplementation),
//             abi.encodeWithSelector(Slasher.initialize.selector, pauserReg, initialOwner)
//         );
//         eigenLayrProxyAdmin.upgradeAndCall(
//             TransparentUpgradeableProxy(payable(address(eigenPodManager))),
//             address(eigenPodManagerImplementation),
//             abi.encodeWithSelector(EigenPodManager.initialize.selector, beaconChainOracle, initialOwner)
//         );
//         generalServiceManager1 = new ServiceManagerMock(investmentManager);

//         generalReg1 = new MiddlewareRegistryMock(
//              generalServiceManager1,
//              investmentManager
//         );

//         beaconChainETHReceiver = new BeaconChainETHReceiver();

//         slashingContracts.push(address(eigenPodManager));
//         investmentManager.slasher().addGloballyPermissionedContracts(slashingContracts);
//         emit log_named_address("og pod owner", podOwner);
        
//     }

//     function testDeployAndVerifyNewEigenPod(bytes memory signature, bytes32 depositDataRoot) public {
//         beaconChainOracle.setBeaconChainStateRoot(0xaf3bf0770df5dd35b984eda6586e6f6eb20af904a5fb840fe65df9a6415293bd);
//         _testDeployAndVerifyNewEigenPod(podOwner, signature, depositDataRoot, false);
//     }

//     //test freezing operator after a beacon chain slashing event
//     function testUpdateSlashedBeaconBalance(bytes memory signature, bytes32 depositDataRoot) public {
//         //make initial deposit
//         testDeployAndVerifyNewEigenPod(signature, depositDataRoot);

//         //get updated proof, set beaconchain state root
//         (beaconStateRoot, beaconStateMerkleProof, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getSlashedDepositProof();

//         beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);
        

//         IEigenPod eigenPod;
//         eigenPod = eigenPodManager.getPod(podOwner);
        
//         bytes32 validatorIndex = bytes32(uint256(0));
//         bytes memory proofs = abi.encodePacked(validatorTreeRoot, beaconStateMerkleProof, validatorRoot, validatorIndex, validatorMerkleProof);
//         eigenPod.verifyBalanceUpdate(pubkey, proofs, validatorContainerFields);
        
//         uint64 validatorBalance = Endian.fromLittleEndianUint64(validatorContainerFields[2]);
//         require(eigenPodManager.getBalance(podOwner) == validatorBalance, "Validator balance not updated correctly");
//         require(investmentManager.slasher().isFrozen(podOwner), "podOwner not frozen successfully");

//     }

//     //test that topping up pod balance after slashing operator prevents freezing
//     function testUpdateSlashedBeaconBalanceWithTopUp(bytes memory signature, bytes32 depositDataRoot) public {
//         //make initial deposit
//         testDeployAndVerifyNewEigenPod(signature, depositDataRoot);

//         //get updated proof, set beaconchain state root
//         (beaconStateRoot, beaconStateMerkleProof, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getSlashedDepositProof();
//         beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);        

//         IEigenPod eigenPod;
//         eigenPod = eigenPodManager.getPod(podOwner);
        
//         bytes32 validatorIndex = bytes32(uint256(0));
//         bytes memory proofs = abi.encodePacked(validatorTreeRoot, beaconStateMerkleProof, validatorRoot, validatorIndex, validatorMerkleProof);
//         eigenPod.topUpPodBalance{value: 16}();

//         eigenPod.verifyBalanceUpdate(pubkey, proofs, validatorContainerFields);
        
//         uint64 validatorBalance = Endian.fromLittleEndianUint64(validatorContainerFields[2]); 
//         require(eigenPodManager.getBalance(podOwner) == validatorBalance, "Validator balance not updated correctly");

//         require(investmentManager.slasher().isFrozen(podOwner) == false, "podOwner frozen mistakenly");

//     }

//     function testDeployNewEigenPodWithWrongPubkey(bytes memory wrongPubkey, bytes memory signature, bytes32 depositDataRoot) public {
//         (beaconStateRoot, beaconStateMerkleProof, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getInitialDepositProof();
//         beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);

//         cheats.startPrank(podOwner);
//         eigenPodManager.stake(wrongPubkey, signature, depositDataRoot);
//         cheats.stopPrank();

//         IEigenPod newPod;
//         newPod = eigenPodManager.getPod(podOwner);

//         bytes32 validatorIndex = bytes32(uint256(0));
//         bytes memory proofs = abi.encodePacked(validatorTreeRoot, beaconStateMerkleProof, validatorRoot, validatorIndex, validatorMerkleProof);
//         cheats.expectRevert(bytes("EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for provided pubkey"));
//         newPod.verifyCorrectWithdrawalCredentials(wrongPubkey, proofs, validatorContainerFields);
//     }

//     function testDeployNewEigenPodWithWrongWithdrawalCreds(address wrongWithdrawalAddress, bytes memory signature, bytes32 depositDataRoot) public {
//         IEigenPod newPod;
//         newPod = eigenPodManager.getPod(podOwner);
//         // make sure that wrongWithdrawalAddress is not set to actual pod address
//         cheats.assume(wrongWithdrawalAddress != address(newPod));
        
//         (beaconStateRoot, beaconStateMerkleProof, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getInitialDepositProof();
//         beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);


//         cheats.startPrank(podOwner);
//         eigenPodManager.stake(pubkey, signature, depositDataRoot);
//         cheats.stopPrank();

//         validatorContainerFields[1] = abi.encodePacked(bytes1(uint8(1)), bytes11(0), wrongWithdrawalAddress).toBytes32(0);

//         bytes32 validatorIndex = bytes32(uint256(0));
//         bytes memory proofs = abi.encodePacked(validatorTreeRoot, beaconStateMerkleProof, validatorRoot, validatorIndex, validatorMerkleProof);
//         cheats.expectRevert(bytes("EigenPod.verifyValidatorFields: Invalid validator fields"));
//         newPod.verifyCorrectWithdrawalCredentials(pubkey, proofs, validatorContainerFields);
//     }

//     function testDeployNewEigenPodWithActiveValidator(bytes memory signature, bytes32 depositDataRoot) public {
//         (beaconStateRoot, beaconStateMerkleProof, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getInitialDepositProof();
//         beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);        

//         cheats.startPrank(podOwner);
//         eigenPodManager.stake(pubkey, signature, depositDataRoot);
//         cheats.stopPrank();

//         IEigenPod newPod;
//         newPod = eigenPodManager.getPod(podOwner);

//         bytes32 validatorIndex = bytes32(uint256(0));
//         bytes memory proofs = abi.encodePacked(validatorTreeRoot, beaconStateMerkleProof, validatorRoot, validatorIndex, validatorMerkleProof);
//         newPod.verifyCorrectWithdrawalCredentials(pubkey, proofs, validatorContainerFields);

//         cheats.expectRevert(bytes("EigenPod.verifyCorrectWithdrawalCredentials: Validator not inactive"));
//         newPod.verifyCorrectWithdrawalCredentials(pubkey, proofs, validatorContainerFields);
//     }

//     // Withdraw eigenpods balance to a contract
//     function testEigenPodsQueuedWithdrawalContract(address operator, bytes memory signature, bytes32 depositDataRoot) public {
//         cheats.assume(operator != address(0));
//         cheats.assume(operator != address(eigenLayrProxyAdmin));
//         cheats.assume(operator != address(beaconChainETHReceiver));

//         //make initial deposit
//         podOwner = address(beaconChainETHReceiver);
//         _testDeployAndVerifyNewEigenPod(podOwner, signature, depositDataRoot, true);


//         //*************************DELEGATION+REGISTRATION OF OPERATOR******************************//
//         _testDelegation(operator, podOwner);

//         cheats.startPrank(operator);
//         investmentManager.slasher().optIntoSlashing(address(generalServiceManager1));
//         cheats.stopPrank();

//         generalReg1.registerOperator(operator, uint32(block.timestamp) + 3 days);
//         //*******************************************************************************************//


//         uint128 balance = eigenPodManager.getBalance(podOwner);

//          IEigenPod newPod;
//         newPod = eigenPodManager.getPod(podOwner);
//         newPod.topUpPodBalance{value : balance}();

//         IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
//         IERC20[] memory tokensArray = new IERC20[](1);
//         uint256[] memory shareAmounts = new uint256[](1);
//         uint256[] memory strategyIndexes = new uint256[](1);
//         IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce =
//             IInvestmentManager.WithdrawerAndNonce({withdrawer: address(beaconChainETHReceiver), nonce: 0});
//         bool undelegateIfPossible = false;
//         {
//             strategyArray[0] = investmentManager.beaconChainETHStrategy();
//             shareAmounts[0] = balance;
//             strategyIndexes[0] = 0;
//         }


//         uint256 podOwnerSharesBefore = investmentManager.investorStratShares(podOwner, investmentManager.beaconChainETHStrategy());
        

//         cheats.warp(uint32(block.timestamp) + 1 days);
//         cheats.roll(uint32(block.timestamp) + 1 days);

//         cheats.startPrank(podOwner);
//         investmentManager.queueWithdrawal(strategyIndexes, strategyArray, tokensArray, shareAmounts, withdrawerAndNonce, undelegateIfPossible);
//         cheats.stopPrank();
//         uint32 queuedWithdrawalStartBlock = uint32(block.number);

//         //*************************DEREGISTER OPERATOR******************************//
//         //now withdrawal block time is before deregistration
//         cheats.warp(uint32(block.timestamp) + 2 days);
//         cheats.roll(uint32(block.timestamp) + 2 days);
        
//         generalReg1.deregisterOperator(operator);

//         //warp past the serve until time, which is 3 days from the beginning.  THis puts us at 4 days past that point
//         cheats.warp(uint32(block.timestamp) + 4 days);
//         cheats.roll(uint32(block.timestamp) + 4 days);
//         //*************************************************************************//

//         uint256 podOwnerSharesAfter = investmentManager.investorStratShares(podOwner, investmentManager.beaconChainETHStrategy());

//         require(podOwnerSharesBefore - podOwnerSharesAfter == balance, "delegation shares not updated correctly");

//         IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal = IInvestmentManager.QueuedWithdrawal({
//             strategies: strategyArray,
//             tokens: tokensArray,
//             shares: shareAmounts,
//             depositor: podOwner,
//             withdrawerAndNonce: withdrawerAndNonce,
//             withdrawalStartBlock: queuedWithdrawalStartBlock,
//             delegatedAddress: delegation.delegatedTo(podOwner)
//         });

//         uint256 receiverBalanceBefore = address(beaconChainETHReceiver).balance;
//         uint256 middlewareTimesIndex = 1;
//         bool receiveAsTokens = true;
//         cheats.startPrank(address(beaconChainETHReceiver));

//         investmentManager.completeQueuedWithdrawal(queuedWithdrawal, middlewareTimesIndex, receiveAsTokens);

//         cheats.stopPrank();

//         require(address(beaconChainETHReceiver).balance - receiverBalanceBefore == shareAmounts[0], "Receiver contract balance not updated correctly");
//     } 

//     // Withdraw eigenpods balance to an EOA
//     function testEigenPodsQueuedWithdrawalEOA(address operator, bytes memory signature, bytes32 depositDataRoot) public {
//         cheats.assume(operator != address(0));
//         cheats.assume(operator != address(eigenLayrProxyAdmin));
//         cheats.assume(operator != podOwner);
//         //make initial deposit
//         testDeployAndVerifyNewEigenPod(signature, depositDataRoot);

//         //*************************DELEGATION+REGISTRATION OF OPERATOR******************************//
//         _testDelegation(operator, podOwner);


//         cheats.startPrank(operator);
//         investmentManager.slasher().optIntoSlashing(address(generalServiceManager1));
//         cheats.stopPrank();

//         generalReg1.registerOperator(operator, uint32(block.timestamp) + 3 days);
//         //*********************************************************************************************//


//         uint128 balance = eigenPodManager.getBalance(podOwner);

//          IEigenPod newPod;
//         newPod = eigenPodManager.getPod(podOwner);
//         newPod.topUpPodBalance{value : balance*(1**18)}();

//         IInvestmentStrategy[] memory strategyArray = new IInvestmentStrategy[](1);
//         IERC20[] memory tokensArray = new IERC20[](1);
//         uint256[] memory shareAmounts = new uint256[](1);
//         uint256[] memory strategyIndexes = new uint256[](1);
//         IInvestmentManager.WithdrawerAndNonce memory withdrawerAndNonce =
//             IInvestmentManager.WithdrawerAndNonce({withdrawer: podOwner, nonce: 0});
//         bool undelegateIfPossible = false;
//         {
//             strategyArray[0] = investmentManager.beaconChainETHStrategy();
//             shareAmounts[0] = balance;
//             strategyIndexes[0] = 0;
//         }


//         uint256 podOwnerSharesBefore = investmentManager.investorStratShares(podOwner, investmentManager.beaconChainETHStrategy());
        

//         cheats.warp(uint32(block.timestamp) + 1 days);
//         cheats.roll(uint32(block.timestamp) + 1 days);

//         cheats.startPrank(podOwner);
//         investmentManager.queueWithdrawal(strategyIndexes, strategyArray, tokensArray, shareAmounts, withdrawerAndNonce, undelegateIfPossible);
//         cheats.stopPrank();
//         uint32 queuedWithdrawalStartBlock = uint32(block.number);

//         //*************************DELEGATION/Stake Update STUFF******************************//
//         //now withdrawal block time is before deregistration
//         cheats.warp(uint32(block.timestamp) + 2 days);
//         cheats.roll(uint32(block.timestamp) + 2 days);
        
//         generalReg1.deregisterOperator(operator);

//         //warp past the serve until time, which is 3 days from the beginning.  THis puts us at 4 days past that point
//         cheats.warp(uint32(block.timestamp) + 4 days);
//         cheats.roll(uint32(block.timestamp) + 4 days);
//         //*************************************************************************//

//         uint256 podOwnerSharesAfter = investmentManager.investorStratShares(podOwner, investmentManager.beaconChainETHStrategy());

//         require(podOwnerSharesBefore - podOwnerSharesAfter == balance, "delegation shares not updated correctly");

//         address delegatedAddress = delegation.delegatedTo(podOwner);
//         IInvestmentManager.QueuedWithdrawal memory queuedWithdrawal = IInvestmentManager.QueuedWithdrawal({
//             strategies: strategyArray,
//             tokens: tokensArray,
//             shares: shareAmounts,
//             depositor: podOwner,
//             withdrawerAndNonce: withdrawerAndNonce,
//             withdrawalStartBlock: queuedWithdrawalStartBlock,
//             delegatedAddress: delegatedAddress
//         });

//         uint256 podOwnerBalanceBefore = podOwner.balance;
//         uint256 middlewareTimesIndex = 1;
//         bool receiveAsTokens = true;
//         cheats.startPrank(podOwner);

//         investmentManager.completeQueuedWithdrawal(queuedWithdrawal, middlewareTimesIndex, receiveAsTokens);

//         cheats.stopPrank();

//         require(podOwner.balance - podOwnerBalanceBefore == shareAmounts[0], "podOwner balance not updated correcty");


//     } 

//     // simply tries to register 'sender' as a delegate, setting their 'DelegationTerms' contract in EigenLayrDelegation to 'dt'
//     // verifies that the storage of EigenLayrDelegation contract is updated appropriately
//     function _testRegisterAsOperator(address sender, IDelegationTerms dt) internal {
//         cheats.startPrank(sender);

//         delegation.registerAsOperator(dt);
//         assertTrue(delegation.isOperator(sender), "testRegisterAsOperator: sender is not a delegate");

//         assertTrue(
//             delegation.delegationTerms(sender) == dt, "_testRegisterAsOperator: delegationTerms not set appropriately"
//         );

//         assertTrue(delegation.isDelegated(sender), "_testRegisterAsOperator: sender not marked as actively delegated");
//         cheats.stopPrank();
//     }

//     function _testDelegateToOperator(address sender, address operator) internal {
//         //delegator-specific information
//         (IInvestmentStrategy[] memory delegateStrategies, uint256[] memory delegateShares) =
//             investmentManager.getDeposits(sender);

//         uint256 numStrats = delegateShares.length;
//         assertTrue(numStrats > 0, "_testDelegateToOperator: delegating from address with no investments");
//         uint256[] memory inititalSharesInStrats = new uint256[](numStrats);
//         for (uint256 i = 0; i < numStrats; ++i) {
//             inititalSharesInStrats[i] = delegation.operatorShares(operator, delegateStrategies[i]);
//         }

//         cheats.startPrank(sender);
//         delegation.delegateTo(operator);
//         cheats.stopPrank();

//         assertTrue(
//             delegation.delegatedTo(sender) == operator,
//             "_testDelegateToOperator: delegated address not set appropriately"
//         );
//         assertTrue(
//             delegation.delegationStatus(sender) == IEigenLayrDelegation.DelegationStatus.DELEGATED,
//             "_testDelegateToOperator: delegated status not set appropriately"
//         );

//         for (uint256 i = 0; i < numStrats; ++i) {
//             uint256 operatorSharesBefore = inititalSharesInStrats[i];
//             uint256 operatorSharesAfter = delegation.operatorShares(operator, delegateStrategies[i]);
//             assertTrue(
//                 operatorSharesAfter == (operatorSharesBefore + delegateShares[i]),
//                 "_testDelegateToOperator: delegatedShares not increased correctly"
//             );
//         }
//     }
//     function _testDelegation(address operator, address staker)
//         internal
//     {   
//         if (!delegation.isOperator(operator)) {
//             _testRegisterAsOperator(operator, IDelegationTerms(operator));
//         }

//         //making additional deposits to the investment strategies
//         assertTrue(delegation.isNotDelegated(staker) == true, "testDelegation: staker is not delegate");
//         _testDelegateToOperator(staker, operator);
//         assertTrue(delegation.isDelegated(staker) == true, "testDelegation: staker is not delegate");

//         IInvestmentStrategy[] memory updatedStrategies;
//         uint256[] memory updatedShares;
//         (updatedStrategies, updatedShares) =
//             investmentManager.getDeposits(staker);
//     }

//     function _testDeployAndVerifyNewEigenPod(address _podOwner, bytes memory signature, bytes32 depositDataRoot, bool isContract) internal {
//         (beaconStateRoot, beaconStateMerkleProof, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getInitialDepositProof();

//         //if the _podOwner is a contract, we get the beacon state proof for the contract-specific withdrawal credential
//         if(isContract) {
//             (beaconStateRoot, beaconStateMerkleProof, validatorContainerFields, validatorMerkleProof, validatorTreeRoot, validatorRoot) = getContractAddressWithdrawalCred();
//         }

//         cheats.startPrank(_podOwner);
//         eigenPodManager.stake(pubkey, signature, depositDataRoot);
//         cheats.stopPrank();

//         beaconChainOracle.setBeaconChainStateRoot(beaconStateRoot);

//         IEigenPod newPod;

//         newPod = eigenPodManager.getPod(_podOwner);
//         emit log_named_address("getPod", address(newPod));

//         bytes32 validatorIndex = bytes32(uint256(0));
//         bytes memory proofs = abi.encodePacked(validatorTreeRoot, beaconStateMerkleProof, validatorRoot, validatorIndex, validatorMerkleProof);
//         newPod.verifyCorrectWithdrawalCredentials(pubkey, proofs, validatorContainerFields);

//         uint64 validatorBalance = Endian.fromLittleEndianUint64(validatorContainerFields[2]);
//         require(eigenPodManager.getBalance(_podOwner) == validatorBalance, "Validator balance not updated correctly");

//         IInvestmentStrategy beaconChainETHStrategy = investmentManager.beaconChainETHStrategy();

//         uint256 beaconChainETHShares = investmentManager.investorStratShares(_podOwner, beaconChainETHStrategy);


//         require(beaconChainETHShares == validatorBalance, "investmentManager shares not updated correctly");
//     }
// }