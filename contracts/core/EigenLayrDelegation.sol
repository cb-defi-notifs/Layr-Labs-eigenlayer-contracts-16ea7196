// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/InvestmentInterfaces.sol";
import "../interfaces/CoreInterfaces.sol";
import "../interfaces/MiddlewareInterfaces.sol";
import "./BLS.sol";

// todo: undelegation fraud proofs
// todo: task specific delegation
contract EigenLayrDelegation {
    address public governer;
    IInvestmentManager public investmentManager;
    // operator => investment strategy => num shares delegated
    mapping(address => mapping(IInvestmentStrategy => uint256))
        public operatorShares;
    // operator => eth on consensus layer delegated
    mapping(address => uint256)
        public consensusLayerEth;
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

    constructor(
        IInvestmentManager _investmentManager,
        uint256 _undelegationFraudProofInterval
    ) {
        governer = msg.sender;
        investmentManager = _investmentManager;
        undelegationFraudProofInterval = _undelegationFraudProofInterval;
    }

    // registers a an address as a delegate along with their delegation terms contract
    function registerAsDelgate(IDelegationTerms dt) external {
        require(
            address(delegationTerms[msg.sender]) == address(0),
            "Delegate has already registered"
        );
        delegationTerms[msg.sender] = dt;
    }

    // delegates a users stake to a certain delegate
    function delegateTo(address operator) external {
        require(
            block.timestamp >
                undelegationFraudProofInterval +
                    lastUndelegationCommit[msg.sender],
            "Last undelegation commit has not been confirmed yet"
        );
        require(
            address(delegationTerms[operator]) != address(0),
            "Delegate has not registered"
        );
        require(
            delegation[msg.sender] == address(0) && !delegated[msg.sender],
            "Delegator has existing delegation"
        );
        // retrieve list of strategies and their shares from investment manager
        IInvestmentStrategy[] memory strategies = investmentManager
            .getStrategies(msg.sender);
        uint256[] memory shares = investmentManager.getStrategyShares(
            msg.sender
        );
        // add strategy shares to delegate's shares
        for (uint256 i = 0; i < strategies.length; i++) {
            operatorShares[operator][strategies[i]] += shares[i];
        }
        // store delegation relation
        delegation[msg.sender] = operator;
        // store that the staker is delegated
        delegated[msg.sender] = true;
        // call into hook in delegationTerms contract
        delegationTerms[operator].onDelegationReceived(
            msg.sender,
            strategies,
            shares
        );
    }

    // commits a stakers undelegate
    function commitUndelegation() external {
        // get their current operator
        address operator = delegation[msg.sender];
        require(
            operator != address(0) && delegated[msg.sender],
            "Delegator does not have existing delegation"
        );
        require(
            block.timestamp >
                undelegationFraudProofInterval +
                    lastUndelegationCommit[msg.sender],
            "Last commit has not been confirmed yet"
        );
        // retrieve list of strategies and their shares from investment manager
        IInvestmentStrategy[] memory strategies = investmentManager
            .getStrategies(msg.sender);
        uint256[] memory shares = investmentManager.getStrategyShares(
            msg.sender
        );
        // subtract strategy shares to delegate's shares
        for (uint256 i = 0; i < strategies.length; i++) {
            operatorShares[operator][strategies[i]] -= shares[i];
        }
        // set time of last undelegation commit
        lastUndelegationCommit[msg.sender] = block.timestamp;
        // set that they are no longer delegated to anyone
        delegated[msg.sender] = false;
        // call into hook in delegationTerms contract
        delegationTerms[operator].onDelegationWithdrawn(
            msg.sender,
            strategies,
            shares
        );
    }

    // finalizes a stakers undelegation commit
    function finalizeUndelegation() external {
        // get their current operator
        address operator = delegation[msg.sender];
        require(
            block.timestamp >
                undelegationFraudProofInterval +
                    lastUndelegationCommit[msg.sender],
            "Last commit has not been confirmed yet"
        );
        require(
            operator != address(0) && !delegated[msg.sender],
            "Delegator is not in the post commit phase"
        );
        // now their operator is the zero address and they are ready to delegate again
        delegation[msg.sender] = address(0);
    }

    // contests a stakers undelegation commit
    function contestUndelegationCommit(IQueryManager queryManager, bytes32 queryHash) external {
        // get their current operator
        address operator = delegation[msg.sender];
        require(
            block.timestamp <
                undelegationFraudProofInterval +
                    lastUndelegationCommit[msg.sender],
            "Last commit has not been confirmed yet"
        );
        require(
            operator != address(0) && !delegated[msg.sender],
            "Delegator is not in the post commit phase"
        );
        
    }
}
