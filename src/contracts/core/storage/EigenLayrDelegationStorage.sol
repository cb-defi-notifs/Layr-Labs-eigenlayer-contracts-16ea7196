// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IInvestmentManager.sol";
import "../../interfaces/IDelegationTerms.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/IServiceFactory.sol";

abstract contract EigenLayrDelegationStorage {
    IInvestmentManager public investmentManager;

    IServiceFactory public serviceFactory;

    // operator => investment strategy => num shares delegated
    mapping(address => mapping(IInvestmentStrategy => uint256))
        public operatorShares;

    mapping(address => IInvestmentStrategy[]) public operatorStrats;

    // operator => eth on consensus layer delegated
    mapping(address => uint256) public consensusLayerEth;

    mapping(address => uint256) public eigenDelegated;

    // operator => delegation terms contract
    mapping(address => IDelegationTerms) public delegationTerms;

    // staker => operator
    mapping(address => address) public delegation;

    // staker => time of last undelegation commit
    mapping(address => uint256) public lastUndelegationCommit;

    // staker => whether they are delegated or not
    mapping(address => bool) public delegated;
    
    // fraud proof interval for undelegation
    uint256 public undelegationFraudProofInterval;
}
