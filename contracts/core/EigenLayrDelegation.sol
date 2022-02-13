// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/InvestmentInterfaces.sol";
import "../interfaces/CoreInterfaces.sol";
import "../interfaces/MiddlewareInterfaces.sol";
import "./BLS.sol";

// todo: task specific delegation
contract EigenLayrDelegation is IEigenLayrDelegation {
    address public governer;
    IInvestmentManager public investmentManager;
    IServiceFactory public serviceFactory;
    // operator => investment strategy => num shares delegated
    mapping(address => mapping(IInvestmentStrategy => uint256))
        public operatorShares;
    mapping(address => IInvestmentStrategy[]) public operatorStrategies;
    // operator => eth on consensus layer delegated
    mapping(address => uint256) public consensusLayerEth;
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
        IServiceFactory _serviceFactory,
        uint256 _undelegationFraudProofInterval
    ) {
        governer = msg.sender;
        investmentManager = _investmentManager;
        serviceFactory = _serviceFactory;
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
            address(delegationTerms[operator]) != address(0),
            "Delegate has not registered"
        );
        require(
            !delegated[msg.sender] &&
                (delegation[msg.sender] == address(0) ||
                    block.timestamp >
                    undelegationFraudProofInterval +
                        lastUndelegationCommit[msg.sender]),
            "Delegator has existing delegation or pending undelegation commitment"
        );
        // retrieve list of strategies and their shares from investment manager
        IInvestmentStrategy[] memory strategies = investmentManager
            .getStrategies(msg.sender);
        uint256[] memory shares = investmentManager.getStrategyShares(
            msg.sender
        );
        // add strategy shares to delegate's shares and add strategy to existing strategies
        for (uint256 i = 0; i < strategies.length; i++) {
            if(operatorShares[operator][strategies[i]] == 0){
                operatorStrategies[operator].push(strategies[i]);
            }
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
    function commitUndelegation(uint256[] calldata strategyIndexes) external {
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
        // subtract strategy shares to delegate's shares and remove from strategy list if no shares remaining
        uint256 strategyIndex = 0;
        for (uint256 i = 0; i < strategies.length; i++) {
            operatorShares[operator][strategies[i]] -= shares[i];
            if(operatorShares[operator][strategies[i]] == 0) {
                require(operatorStrategies[operator][strategyIndexes[strategyIndex]] == strategies[i], "Incorrect strategy index");
                operatorStrategies[operator][strategyIndexes[strategyIndex]] = operatorStrategies[operator][operatorStrategies[operator].length];
                operatorStrategies[operator].pop();
            }
        }
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
            operator != address(0) && !delegated[msg.sender],
            "Delegator is not in the post commit phase"
        );
        // set time of last undelegation commit
        lastUndelegationCommit[msg.sender] = block.timestamp;
    }

    // contests a stakers undelegation commit
    function contestUndelegationCommit(
        address staker,
        IQueryManager queryManager,
        bytes32 queryHash
    ) external {
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
        require(
            serviceFactory.queryManagerExists(queryManager),
            "QueryManager was not deployed through factory"
        );
        //ongoing query exists at time of undelegation commit
        require(
            lastUndelegationCommit[staker] >
                queryManager.getQueryCreationTime(queryHash) &&
                lastUndelegationCommit[staker] <
                queryManager.getQueryCreationTime(queryHash) +
                    queryManager.getQueryDuration(),
            "Given query is inactive"
        );
        //slash here
    }

    function getDelegationTerms(address operator) public view returns(IDelegationTerms) {
        return delegationTerms[operator];
    }

    function getOperatorShares(address operator) public view returns(IInvestmentStrategy[] memory) {
        return operatorStrategies[operator];
    }
}
