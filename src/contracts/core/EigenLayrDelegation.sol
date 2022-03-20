// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IDelegationTerms.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IServiceFactory.sol";
import "../utils/Initializable.sol";
import "../utils/Governed.sol";
import "./storage/EigenLayrDelegationStorage.sol";

// todo: task specific delegation
contract EigenLayrDelegation is Initializable, Governed, EigenLayrDelegationStorage, IEigenLayrDelegation {

    function initialize(
        IInvestmentManager _investmentManager,
        IServiceFactory _serviceFactory,
        uint256 _undelegationFraudProofInterval
    ) initializer external {
        _transferGovernor(msg.sender);
        investmentManager = _investmentManager;
        serviceFactory = _serviceFactory;
        undelegationFraudProofInterval = _undelegationFraudProofInterval;
    }

    // registers a an address as a delegate along with their delegation terms contract
    /// @notice This will be called by a staker to register itself as a delegate with respect 
    ///         to a certain operator. 
    /// @param dt is the delegation terms contract that staker has agreed to with the operator.   
    function registerAsDelgate(IDelegationTerms dt) external {
        require(
            address(delegationTerms[msg.sender]) == address(0),
            "Delegate has already registered"
        );
        // store the address of the delegation contract that staker has agreed to.
        delegationTerms[msg.sender] = dt;
    }

    // staker acts as own operator
    /// @notice This will be called by a staker if it wants to act as its own operator. 
    function delegateToSelf() external {
        require(
            address(delegationTerms[msg.sender]) == address(0),
            "Staker has already agreed to delegate its assets to some other operator and so cannot be public operator"
        );
        require(
            isNotDelegated(msg.sender),
            "Staker has existing delegation or pending undelegation commitment"
        );
        // store delegation relation that the staker (msg.sender) is its own operator (msg.sender)
        delegation[msg.sender] = msg.sender;
        // store the flag that the staker is delegated
        delegated[msg.sender] = true;
    }

    // delegates a users stake to a certain delegate
    /// @notice This will be called by a registered delegator to delegate its assets to some operator
    /// @param operator is the operator to whom delegator (msg.sender) is delegating its assets 
    function delegateTo(address operator) external {
        // CRITIC: should there be a check that operator != msg.sender?
        require(
            address(delegationTerms[operator]) != address(0),
            "Staker has not registered as a delegate yet. Please call registerAsDelgate(IDelegationTerms dt) first."
        );
        require(
            isNotDelegated(msg.sender),
            "Staker has existing delegation or pending undelegation commitment"
        );
        // retrieve list of strategies and their shares from investment manager
        (
            IInvestmentStrategy[] memory strategies,
            uint256[] memory shares,
            uint256 consensusLayrEthDeposited,
            uint256 eigenAmount
        ) = investmentManager.getDeposits(msg.sender);


        // add strategy shares to delegate's shares and add strategy to existing strategies
        for (uint256 i = 0; i < strategies.length; i++) {
            if (operatorShares[operator][strategies[i]] == 0) {
                // if no asset has been delegated yet to this strategy in the operator's portfolio,
                // then add it to the portfolio of strategies of the operator
                operatorStrats[operator].push(strategies[i]);
            }
            // update the total share deposited in favor of the startegy in the operator's portfolio
            operatorShares[operator][strategies[i]] += shares[i];
        }

        // update the total ETH delegated to the operator 
        consensusLayerEth[operator] += consensusLayrEthDeposited;

        // update the total EIGEN deposited with the operator 
        eigenDelegated[operator] += eigenAmount;

        // record delegation relation between the delegator and operator
        delegation[msg.sender] = operator;

        // record that the staker is delegated
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
        // CRITIC: If a staker is giving the data for strategyIndexes, then 
        // there is a potential concurrency problem. 
        // get their current operator
        address operator = delegation[msg.sender];
        require(
            operator != address(0) && delegated[msg.sender],
            "Staker does not have existing delegation"
        );
        require(
            block.timestamp >
                undelegationFraudProofInterval +
                    lastUndelegationCommit[msg.sender],
            "Last commit has not been confirmed yet"
        );
        // if not delegated to self
        if (operator != msg.sender) {
            // retrieve list of strategies and their shares from investment manager
            (
                IInvestmentStrategy[] memory strategies,
                uint256[] memory shares,
                uint256 consensusLayrEthDeposited,
                uint256 eigenAmount
            ) = investmentManager.getDeposits(msg.sender);
            // subtract strategy shares to delegate's shares and remove from strategy list if no shares remaining
            uint256 strategyIndex = 0;
            for (uint256 i = 0; i < strategies.length; i++) {
                operatorShares[operator][strategies[i]] -= shares[i];
                if (operatorShares[operator][strategies[i]] == 0) {
                    // CRITIC: strategyindex is always 0. This doesn't look right. Should increment 
                    // whenever the above condition is satisfied
                    require(
                        operatorStrats[operator][
                            strategyIndexes[strategyIndex]
                        ] == strategies[i],
                        "Incorrect strategy index"
                    );
                    operatorStrats[operator][
                        strategyIndexes[strategyIndex]
                    ] = operatorStrats[operator][
                        operatorStrats[operator].length
                    ];
                    operatorStrats[operator].pop();
                }
            }
            consensusLayerEth[operator] -= consensusLayrEthDeposited;
            eigenDelegated[operator] -= eigenAmount;
            // set that they are no longer delegated to anyone
            delegated[msg.sender] = false;
            // call into hook in delegationTerms contract
            delegationTerms[operator].onDelegationWithdrawn(
                msg.sender,
                strategies,
                shares
            );
        } else {
            delegated[msg.sender] = false;
        }
    }

    // finalizes a stakers undelegation commit
    function finalizeUndelegation() external {
        // get their current operator
        address operator = delegation[msg.sender];
        require(
            operator != address(0) && !delegated[msg.sender],
            "Staker is not in the post commit phase"
        );
        require(
            block.timestamp >
                lastUndelegationCommit[msg.sender] +
                    undelegationFraudProofInterval,
            "Staker is not in the post commit phase"
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
            "Staker is not in the post commit phase"
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

    function isNotDelegated(address staker) public view returns (bool) {
        return
            !delegated[staker] &&
            (delegation[staker] == address(0) ||
                block.timestamp >
                undelegationFraudProofInterval +
                    lastUndelegationCommit[staker]);
    }

    function getDelegationTerms(address operator)
        public
        view
        returns (IDelegationTerms)
    {
        return delegationTerms[operator];
    }

    function getOperatorShares(address operator)
        public
        view
        returns (IInvestmentStrategy[] memory)
    {
        return operatorStrats[operator];
    }

    function getControlledEthStake(address operator)
        external
        view
        returns (IInvestmentStrategy[] memory, uint256[] memory, uint256)
    {
        if(delegation[operator] == operator) {
            (IInvestmentStrategy[] memory strats, uint256[] memory shares, uint256 consensusLayerEthForOperator,) = investmentManager.getDeposits(operator);
            return (strats, shares, consensusLayerEthForOperator);
        } else {
            uint256[] memory shares = new uint256[](operatorStrats[operator].length);
            for (uint256 i = 0; i < shares.length; i++) {
                shares[i] = operatorShares[operator][operatorStrats[operator][i]];
            }
            return (operatorStrats[operator], shares, consensusLayerEth[operator]);
        }
    }

    function getUnderlyingEthDelegated(address operator)
        external
        returns (uint256)
    {
        uint256 weight;
        if (delegation[operator] == operator) {
            IInvestmentStrategy[] memory investorStrats = investmentManager
                .getStrategies(operator);
            uint256[] memory investorShares = investmentManager
                .getStrategyShares(operator);
            for (uint256 i = 0; i < investorStrats.length; i++) {
                weight += investorStrats[i].underlyingEthValueOfShares(
                    investorShares[i]
                );
            }
        } else {
            IInvestmentStrategy[] memory investorStrats = operatorStrats[
                operator
            ];
            for (uint256 i = 0; i < investorStrats.length; i++) {
                weight += investorStrats[i].underlyingEthValueOfShares(
                    operatorShares[operator][investorStrats[i]]
                );
            }
        }
        return weight;
    }

    function getUnderlyingEthDelegatedView(address operator)
        external
        view
        returns (uint256)
    {
        uint256 weight;
        if (delegation[operator] == operator) {
            IInvestmentStrategy[] memory investorStrats = investmentManager
                .getStrategies(operator);
            uint256[] memory investorShares = investmentManager
                .getStrategyShares(operator);
            for (uint256 i = 0; i < investorStrats.length; i++) {
                weight += investorStrats[i].underlyingEthValueOfSharesView(
                    investorShares[i]
                );
            }
        } else {
            IInvestmentStrategy[] memory investorStrats = operatorStrats[
                operator
            ];
            for (uint256 i = 0; i < investorStrats.length; i++) {
                weight += investorStrats[i].underlyingEthValueOfSharesView(
                    operatorShares[operator][investorStrats[i]]
                );
            }
        }
        return weight;
    }

    function getConsensusLayerEthDelegated(address operator)
        external
        view
        returns (uint256)
    {
        return
            delegation[operator] == operator
                ? investmentManager.getConsensusLayerEth(operator)
                : consensusLayerEth[operator];
    }

    function getEigenDelegated(address operator)
        external
        view
        returns (uint256)
    {
        return
            delegation[operator] == operator
                ? investmentManager.getEigen(operator)
                : eigenDelegated[operator];
    }
}
