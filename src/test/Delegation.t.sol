// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";


import "../test/Deployer.t.sol";

import "../contracts/libraries/BytesLib.sol";

import "../contracts/middleware/ServiceManagerBase.sol";

import "ds-test/test.sol";

import "./CheatCodes.sol";

contract Delegator is EigenLayrDeployer {
    using BytesLib for bytes;
    uint shares;
    address[2] public delegators;
    ServiceManagerBase serviceManager;
    VoteWeigherBase voteWeigher;
    Repository repository;
    IRepository newRepository;
    ServiceFactory factory;
    IRegistrationManager regManager;
    DelegationTerms dt;

    uint256 amountEigenToDeposit = 50;
    uint256 amountEthToDeposit = 40;

    constructor(){
        delegators = [acct_0, acct_1];
    }

       function setUp() override public  {
        eigenLayrProxyAdmin = new ProxyAdmin();

        //eth2 deposit contract
        depositContract = new DepositContract();
        //deploy eigen. send eigen tokens to an address where they won't trigger failure for 'transfer to non ERC1155Receiver implementer,'
        eigen = new Eigen(address(this));

        deposit = new EigenLayrDeposit(consensusLayerDepositRoot);
        deposit = EigenLayrDeposit(address(new TransparentUpgradeableProxy(address(deposit), address(eigenLayrProxyAdmin), "")));
        //do stuff this eigen token here
        delegation = new EigenLayrDelegation();
        delegation = EigenLayrDelegation(address(new TransparentUpgradeableProxy(address(delegation), address(eigenLayrProxyAdmin), "")));
        slasher = new Slasher(investmentManager, address(this));
        serviceFactory = new ServiceFactory(investmentManager, delegation);
        investmentManager = new InvestmentManager(eigen, delegation, serviceFactory);
        investmentManager = InvestmentManager(address(new TransparentUpgradeableProxy(address(investmentManager), address(eigenLayrProxyAdmin), "")));
        //used in the one investment strategy
        weth = new ERC20PresetFixedSupply(
            "weth",
            "WETH",
            wethInitialSupply,
            address(this)
        );
        //do stuff with weth
        strat = new WethStashInvestmentStrategy();
        strat = WethStashInvestmentStrategy(address(new TransparentUpgradeableProxy(address(strat), address(eigenLayrProxyAdmin), "")));
        strat.initialize(address(investmentManager), weth);

        IInvestmentStrategy[] memory strats = new IInvestmentStrategy[](3);

        HollowInvestmentStrategy temp = new HollowInvestmentStrategy();
        temp.initialize(address(investmentManager));
        strats[0] = temp;
        temp = new HollowInvestmentStrategy();
        temp.initialize(address(investmentManager));
        strats[1] = temp;
        strats[2] = IInvestmentStrategy(address(strat));
        // WETH strategy added to InvestmentManager
        strategies[0] = IInvestmentStrategy(address(strat));

        address governor = address(this);
        investmentManager.initialize(
            strats,
            slasher,
            governor,
            address(deposit)
        );

        delegation.initialize(
            investmentManager,
            serviceFactory,
            slasher,
            undelegationFraudProofInterval
        );

        dataLayrPaymentChallengeFactory = new DataLayrPaymentChallengeFactory();
        dataLayrDisclosureChallengeFactory = new DataLayrDisclosureChallengeFactory();

        uint256 feePerBytePerTime = 1;
        dlsm = new DataLayrServiceManager(
            delegation,
            weth,
            weth,
            feePerBytePerTime,
            dataLayrPaymentChallengeFactory,
            dataLayrDisclosureChallengeFactory
        );
        dl = new DataLayr();

        dlRepository = new Repository(delegation, investmentManager);

        // IInvestmentStrategy[] memory strats = new IInvestmentStrategy[](1);
        // strats[0] = IInvestmentStrategy(address(strat));
        dlRegVW = new DataLayrVoteWeigher(Repository(address(dlRepository)), delegation, investmentManager, consensusLayerEthToEth, strats);

        Repository(address(dlRepository)).initialize(
            dlRegVW,
            dlsm,
            dlRegVW,
            timelockDelay
        );

        dl.setRepository(dlRepository);
        dlsm.setRepository(dlRepository);
        dlsm.setDataLayr(dl);

        deposit.initialize(depositContract, investmentManager, dlsm);

        liquidStakingMockToken = new WETH();
        liquidStakingMockStrat = new WethStashInvestmentStrategy();
        liquidStakingMockStrat.initialize(address(investmentManager), IERC20(address(liquidStakingMockToken)));

        //loads hardcoded signer set
        _setSigners();
    }


    function testinitiateDelegation() public {

        //_initializeServiceManager();
        
        _testinitiateDelegation(1e10);

        //servicemanager pays out rewards
        _payRewards();
        
        //withdraw rewards
        // uint32[] memory indices = [0];
        // dt.withdrawPendingRewards(indices);
        // (
        //     IInvestmentStrategy[] memory strategies,
        //     uint256[] memory shares,
        //     uint256 eigenAmount
        // ) = investmentManager.getDeposits(delegator);

        // for(uint i; i < delegators.length; i++){
        //     dt.onDelegationWithdrawn(delegators[i], strategies, shares);
        // }

    }
    function _testinitiateDelegation(uint256 amountToDeposit) public {

        emit log_named_address("DLSM", address(dlsm));
        //setting up operator's delegation terms
        weth.transfer(registrant, 1e5);
        cheats.startPrank(registrant);
        dt = _setDelegationTerms(registrant);
        delegation.registerAsDelegate(dt);
        cheats.stopPrank();
        
        for(uint i; i < delegators.length; i++){
            //initialize weth, eigen and eth balances for delegator
            eigen.safeTransferFrom(address(this), delegators[i], 0, amountEigenToDeposit, "0x");
            weth.transfer(delegators[i], amountToDeposit);
            cheats.deal(delegators[i], amountEthToDeposit);
            


            cheats.startPrank(delegators[i]);

            //depositing delegator's eth into consensus layer
            deposit.depositEthIntoConsensusLayer{value: amountEthToDeposit}("0x", "0x", depositContract.get_deposit_root());

            //deposit delegator's eigen into investment manager
            eigen.setApprovalForAll(address(investmentManager), true);
            investmentManager.depositEigen(amountEigenToDeposit);
            
            //depost weth into investment manager
            weth.approve(address(investmentManager), type(uint256).max);
            investmentManager.depositIntoStrategy(
                delegators[i],
                strat,
                weth,
                amountToDeposit);

            //delegate delegators deposits to operator
            delegation.delegateTo(registrant);
            cheats.stopPrank();
        }
        emit log("yup");

        cheats.startPrank(registrant);
        emit log("yup34"); 
        uint8 registrantType = 3;
        string memory socket = "fe";

        emit log_uint(weth.totalSupply());

        //register operator with vote weigher so they can get payment
        dlRegVW.registerOperator(registrantType, socket, abi.encodePacked(bytes24(0)));
        cheats.stopPrank();

    }

    function _payRewards() internal {

        emit log_named_uint("hello", dlsm.dumpNumber());

        bytes memory header = bytes(
            "0x0102030405060708091011121314151617181920"
        );

        weth.transfer(storer, 10e10);
        cheats.prank(storer);
        weth.approve(address(dlsm), type(uint256).max);
        cheats.prank(storer);

        dlsm.initDataStore(
            header,
            1e6,
            600
        );

        bytes32 headerHash = keccak256(header);
        (
            uint48 dataStoreDumpNumber,
            uint32 dataStoreInitTime,
            uint32 dataStorePeriodLength,
            bool dataStoreCommitted
        ) = dl.dataStores(headerHash);

       
        cheats.startPrank(registrant);
        weth.approve(address(dlsm), type(uint256).max);

        uint256 currBalance = weth.balanceOf(address(dt));
        uint120 amountRewards = 10;

        dlsm.commitPayment(dataStoreDumpNumber, amountRewards);
        cheats.warp(block.timestamp + dlsm.paymentFraudProofInterval()+1);
        dlsm.redeemPayment();

        assertTrue(weth.balanceOf(address(dt)) == currBalance + amountRewards, "rewards not transferred to delegation terms contract");

        emit log_named_uint("operator balance before", weth.balanceOf(registrant));
        dt.operatorWithdrawal();
        emit log_named_uint("operator balance after", weth.balanceOf(registrant));



        cheats.stopPrank();

    }

    function _setDelegationTerms(address operator) internal returns (DelegationTerms){
        dt = _initializeDelegationTerms(operator);
        return dt;

    }

    function _initializeDelegationTerms(address operator) internal returns (DelegationTerms) {
        address[] memory paymentTokens = new address[](0);
        uint16 _MAX_OPERATOR_FEE_BIPS = 500;
        uint16 _operatorFeeBips = 500;
        dt = 
            new DelegationTerms(
                operator,
                investmentManager,
                paymentTokens,
                factory,
                address(delegation),
                _MAX_OPERATOR_FEE_BIPS,
                _operatorFeeBips
            );
        assertTrue(address(dt) != address(0), "_deployDelegationTerms: DelegationTerms failed to deploy");
        dt.addPaymentToken(address(weth));
        return dt;

    }





















}