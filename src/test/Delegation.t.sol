// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";


import "../test/Deployer.t.sol";

import "../contracts/libraries/BytesLib.sol";

import "ds-test/test.sol";

import "./CheatCodes.sol";

contract Delegator is EigenLayrDeployer {
    using BytesLib for bytes;
    uint shares;
    address[2] public delegators;
    DelegationTerms public dt;

    constructor(){
        delegators = [acct_0, acct_1];
    }


    function _init() public {

    }
    function testinitiateDelegation() public {
        setUp();
        _testinitiateDelegation(1e12);

        //servicemanager pays out rewards
        //_payRewards(50);
        
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

        //setting up operator's delegation terms
        cheats.startPrank(registrant);
        dt = _setDelegationTerms(registrant);
        delegation.registerAsDelegate(dt);
        cheats.stopPrank();

        for(uint i; i < delegators.length; i++){
            //initialize weth, eigen and eth balances for delegator
            eigen.safeTransferFrom(address(this), delegators[i], 0, amountToDeposit, "0x");
            weth.transfer(delegators[i], amountToDeposit);
            cheats.deal(delegators[i], amountToDeposit);

            cheats.startPrank(delegators[i]);

            //depositing delegator's eth into consensus layer
            deposit.depositEthIntoConsensusLayer{value: amountToDeposit}("0x", "0x", depositContract.get_deposit_root());

            //deposit delegator's eigen into investment manager
            eigen.setApprovalForAll(address(investmentManager), true);
            investmentManager.depositEigen(amountToDeposit);
              
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
    }

    function _payRewards(uint256 amount) internal {
        dlRepository = new Repository(delegation, investmentManager);
        dataLayrPaymentChallengeFactory = new DataLayrPaymentChallengeFactory();
        dataLayrDisclosureChallengeFactory = new DataLayrDisclosureChallengeFactory();

        uint256 feePerBytePerTime = 1;
        // dlsm = new DataLayrServiceManager(
        //     delegation,
        //     weth,
        //     weth,
        //     feePerBytePerTime,
        //     dataLayrPaymentChallengeFactory,
        //     dataLayrDisclosureChallengeFactory
        // );

        cheats.startPrank(address(dlsm));
        dt.payForService(weth, amount);
        cheats.stopPrank();
    }

    function _setDelegationTerms(address operator) internal returns (DelegationTerms){
        dt = _initializeDelegationTerms(operator);
        return dt;

    }

    function _initializeDelegationTerms(address operator) internal returns (DelegationTerms) {
        address[] memory paymentTokens = new address[](1);
        paymentTokens[0] = address(weth);
        uint16 _MAX_OPERATOR_FEE_BIPS = 500;
        uint16 _operatorFeeBips = 500;
        dt = 
            new DelegationTerms(
                operator,
                investmentManager,
                paymentTokens,
                serviceFactory,
                address(delegation),
                _MAX_OPERATOR_FEE_BIPS,
                _operatorFeeBips
            );
        assertTrue(address(dt) != address(0), "_deployDelegationTerms: DelegationTerms failed to deploy");
        return dt;

    }





















}