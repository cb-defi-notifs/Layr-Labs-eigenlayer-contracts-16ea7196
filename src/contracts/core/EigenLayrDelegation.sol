// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../utils/Initializable.sol";
import "../utils/Governed.sol";
import "./EigenLayrDelegationStorage.sol";
import "../libraries/SignatureCompaction.sol";

// TODO: updating of stored addresses by governance?

/**
 * @notice  This is the contract for delegation in EigenLayr. The main functionalities of this contract are
 *            - for enabling any staker to register as a delegate and specify the delegation terms it has agreed to
 *            - for enabling anyone to register as an operator
 *            - for a registered delegator to delegate its stake to the operator of its agreed upon delegation terms contract
 *            - for a delegator to undelegate its assets from EigenLayr
 *            - for anyone to challenge a delegator's claim to have fulfilled all its obligation before undelegation
 */
contract EigenLayrDelegation is
    Initializable,
    Governed,
    EigenLayrDelegationStorage
{
    /// @notice EIP-712 Domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(DOMAIN_TYPEHASH, bytes("EigenLayr"), block.chainid)
        );
    }

    function initialize(
        IInvestmentManager _investmentManager,
        IServiceFactory _serviceFactory,
        Slasher _slasher,
        uint256 _undelegationFraudProofInterval
    ) external initializer {
        _transferGovernor(msg.sender);
        investmentManager = _investmentManager;
        serviceFactory = _serviceFactory;
        slasher = _slasher;
        undelegationFraudProofInterval = _undelegationFraudProofInterval;
    }

    /// @notice This will be called by an operator to register itself as a delegate that stakers
    ///         can choose to delegate to.
    /// @param dt is the delegation terms contract that operator has for those who delegate to them.
    function registerAsDelegate(IDelegationTerms dt) external {
        require(
            address(delegationTerms[msg.sender]) == address(0),
            "Delegate has already registered"
        );
        // store the address of the delegation contract that operator is providing.
        delegationTerms[msg.sender] = dt;
        // TODO: add this back in once delegating to your own delegationTerms will no longer break things
        // _delegate(msg.sender, msg.sender);
    }

    /// @notice This will be called by a staker if it wants to act as its own operator.
    function delegateToSelf() external {
        require(
            address(delegationTerms[msg.sender]) == address(0),
            "Delegate has already registered"
        );
        require(
            isNotDelegated(msg.sender),
            "Staker has existing delegation or pending undelegation commitment"
        );
        // store delegation relation that the staker (msg.sender) is its own operator (msg.sender)
        delegation[msg.sender] = msg.sender;
        // store the flag that the staker is delegated
        delegated[msg.sender] = DelegationStatus.DELEGATED;
    }

    /// @notice This will be called by a registered delegator to delegate its assets to some operator
    /// @param operator is the operator to whom delegator (msg.sender) is delegating its assets
    function delegateTo(address operator) external {
        _delegate(msg.sender, operator);
    }

    function delegateToBySignature(
        address delegator,
        address operator,
        uint256 nonce,
        uint256 expiry,
        bytes32 r,
        bytes32 vs
    ) external {
        require(
            delegationNonces[delegator] == nonce,
            "invalid delegation nonce"
        );
        require(
            expiry == 0 || expiry <= block.timestamp,
            "delegation signature expired"
        );
        bytes32 structHash = keccak256(
            abi.encode(DELEGATION_TYPEHASH, delegator, operator, nonce, expiry)
        );
        bytes32 digestHash = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );
        //check validity of signature
        address recoveredAddress = SignatureCompaction.ecrecoverPacked(
            digestHash,
            r,
            vs
        );
        require(
            recoveredAddress != address(0),
            "delegateToBySignature: bad signature"
        );
        require(
            recoveredAddress == delegator,
            "delegateToBySignature: sig not from delegator"
        );
        // increment delegator's delegationNonce
        ++delegationNonces[delegator];
        _delegate(delegator, operator);
    }

    function operatorStratsOfInterest(address operator, uint256 index) public view returns (IInvestmentStrategy) {
        return _operatorStratsOfInterest[operator][index];
    }

    function operatorStratsOfInterestLength(address operator) public view returns (uint256) {
        return _operatorStratsOfInterest[operator].length;
    }

    function addOperatorStrats(IInvestmentStrategy[] calldata stratsToAdd) external {
        uint256 stratsLength = stratsToAdd.length;
        // TODO: ENSURE NO DUPLICATES ARE ADDED!
        for (uint256 i = 0; i < stratsLength;) {
            _operatorStratsOfInterest[msg.sender].push(stratsToAdd[i]);
            unchecked {
                ++i;
            }
        }
    }

    // internal function implementing the delegation of 'delegator' to 'operator'
    function _delegate(address delegator, address operator) internal {
        require(
            address(delegationTerms[operator]) != address(0),
            "Staker has not registered as a delegate yet. Please call registerAsDelegate(IDelegationTerms dt) first."
        );
        require(
            isNotDelegated(delegator),
            "Staker has existing delegation or pending undelegation commitment"
        );

        // record delegation relation between the delegator and operator
        delegation[delegator] = operator;

        // record that the staker is delegated
        delegated[delegator] = DelegationStatus.DELEGATED;

        uint256 stratsLength = _operatorStratsOfInterest[operator].length;
        uint96[] memory delegatorShares = new uint96[](stratsLength);
        for (uint256 i = 0; i < stratsLength;) {
            // retrieve share amount from investment manager
            IInvestmentStrategy strat = _operatorStratsOfInterest[operator][i];
            delegatorShares[i] = uint96(investmentManager.investorStratShares(delegator, strat));
            // add strategy shares to delegate's shares
            operatorShares[operator][strat] += delegatorShares[i];
            unchecked {
                ++i;
            }
        }
        uint256 eigenAmount = investmentManager.getEigen(delegator);

        // update the total EIGEN deposited with the operator
        eigenDelegated[operator] += eigenAmount;

        // call into hook in delegationTerms contract
        IDelegationTerms dt = delegationTerms[operator];
        if (address(dt) != operator) {
            delegationTerms[operator].onDelegationReceived(
                delegator,
                delegatorShares
            );
        }
    }

    /// @notice This function is used to notify the system that a delegator wants to stop
    ///         participating in the functioning of EigenLayr.
    /// @param strategyIndexes is the array of indices whose corresponding strategies in
    ///        the array "operatorStrats[operator]" has their shares go to zero
    ///        because of undelegation by the delegator.
    /// @dev (1) Here is a formal explanation in how this function uses strategyIndexes:
    ///          Suppose operatorStrats[operator] = [s_1, s_2, s_3, ..., s_n].
    ///          Consider that, as a consequence of undelegation by delegator,
    ///             for strategy s in {s_{i1}, s_{i2}, ..., s_{ik}}, we have
    ///                 operatorShares[operator][s] = 0.
    ///          Here, i1, i2, ..., ik are the indices of the corresponding strategies
    ///          in operatorStrats[operator].
    ///          Then, strategyIndexes = [i1, i2, ..., ik].
    ///      (2) In order to notify the system that delegator wants to undelegate,
    ///          it is necessary to make sure that delegator is not within challenge
    ///          window for a previous undelegation.
    function commitUndelegation(uint256[] calldata strategyIndexes) external {
        // get the current operator for the delegator (msg.sender)
        address operator = delegation[msg.sender];
        require(
            operator != address(0) &&
                delegated[msg.sender] == DelegationStatus.DELEGATED,
            "Staker does not have existing delegation"
        );

        // checks that delegator is not within challenge window for a previous undelegation
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
                uint256 eigenAmount
            ) = investmentManager.getDeposits(msg.sender);

            // subtract strategy shares from delegate's shares and remove the strategy from delegate's strategy list if no shares remaining
            uint256 strategyIndex = 0;
            for (uint256 i = 0; i < strategies.length; ) {
                operatorShares[operator][strategies[i]] -= shares[i];
                if (operatorShares[operator][strategies[i]] == 0) {
                    // if the strategy matches with the strategy index provided
                    if (
                        operatorStrats[operator][
                            strategyIndexes[strategyIndex]
                        ] == strategies[i]
                    ) {
                        //replace the strategy with the last strategy in the list
                        operatorStrats[operator][
                            strategyIndexes[strategyIndex]
                        ] = operatorStrats[operator][
                            operatorStrats[operator].length - 1
                        ];
                    } else {
                        //loop through all of the strategies, find the right one, then replace
                        uint256 stratsLength = operatorStrats[operator].length;
                        for (uint256 j = 0; j < stratsLength; ) {
                            if (operatorStrats[operator][j] == strategies[i]) {
                                //replace the strategy with the last strategy in the list
                                operatorStrats[operator][j] = operatorStrats[
                                    operator
                                ][operatorStrats[operator].length - 1];
                                break;
                            }
                            unchecked {
                                ++j;
                            }
                        }
                    }
                    operatorStrats[operator].pop();
                    unchecked {
                        ++strategyIndex;
                    }
                }
                unchecked {
                    ++i;
                }
            }

            // update the Eigen delegated to the operator
            eigenDelegated[operator] -= eigenAmount;

            // set that they are no longer delegated to anyone
            delegated[msg.sender] = DelegationStatus.UNDELEGATION_COMMITED;

            // call into hook in delegationTerms contract
            delegationTerms[operator].onDelegationWithdrawn(
                msg.sender,
                strategies,
                shares
            );
        } else {
            delegated[msg.sender] = DelegationStatus.UNDELEGATION_COMMITED;
        }
    }

    function reduceOperatorShares(
        address operator,
        uint256[] calldata operatorStrategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata shares
    ) external {
        require(
            msg.sender == address(investmentManager),
            "onlyInvestmentManager"
        );

        // subtract strategy shares from delegate's shares and remove the strategy from delegate's strategy list if no shares remaining
        uint256 strategyIndex = 0;
        for (uint256 i = 0; i < strategies.length; ) {
            operatorShares[operator][strategies[i]] -= shares[i];
            if (operatorShares[operator][strategies[i]] == 0) {
                // if the strategy matches with the strategy index provided
                if (
                    operatorStrats[operator][
                        operatorStrategyIndexes[strategyIndex]
                    ] == strategies[i]
                ) {
                    //replace the strategy with the last strategy in the list
                    operatorStrats[operator][
                        operatorStrategyIndexes[strategyIndex]
                    ] = operatorStrats[operator][
                        operatorStrats[operator].length - 1
                    ];
                } else {
                    //loop through all of the strategies, find the right one, then replace
                    uint256 stratsLength = operatorStrats[operator].length;
                    for (uint256 j = 0; j < stratsLength; ) {
                        if (operatorStrats[operator][j] == strategies[i]) {
                            //replace the strategy with the last strategy in the list
                            operatorStrats[operator][j] = operatorStrats[
                                operator
                            ][operatorStrats[operator].length - 1];
                            break;
                        }
                        unchecked {
                            ++j;
                        }
                    }
                }
                operatorStrats[operator].pop();
                unchecked {
                    ++strategyIndex;
                }
            }
            unchecked {
                ++i;
            }
        }
        //TOOD: call into delegationTerms contract as well?
    }

    /// @notice This function must be called by a delegator to notify that its stake is
    ///         no longer active on any queries, which in turn launches the challenge
    ///         period.
    function finalizeUndelegation() external {
        require(
            delegated[msg.sender] == DelegationStatus.UNDELEGATION_COMMITED,
            "Staker is not in the post commit phase"
        );

        // checks that delegator is not within challenger period for a previous undelegation
        require(
            block.timestamp >
                lastUndelegationCommit[msg.sender] +
                    undelegationFraudProofInterval,
            "Staker is not in the post commit phase"
        );

        // set time of last undelegation commit which is the beginning of the corresponding
        // challenge period.
        lastUndelegationCommit[msg.sender] = block.timestamp;
        delegated[msg.sender] = DelegationStatus.UNDELEGATION_FINALIZED;
    }

    /// @notice This function can be called by anyone to challenger whether a delegator has
    ///         finalized its undelegation after satisfying its obligations in EigenLayr or not.
    /// @param staker is the delegator against whom challenge is being raised,
    /// @param repository is the contract with whom the query for which delegator hasn't finished
    ///        its obligation yet, was deployed,
    /// @param serviceObjectHash is the hash of the query for whom staker hasn't finished its obligations
    function contestUndelegationCommit(
        address staker,
        bytes32 serviceObjectHash,
        IServiceFactory serviceFactory,
        IRepository repository,
        IRegistrationManager registrationManager
    ) external {
        address operator = delegation[staker];

        require(
            block.timestamp <
                undelegationFraudProofInterval + lastUndelegationCommit[staker],
            "Challenge was raised after the end of challenge period"
        );

        require(
            delegated[staker] == DelegationStatus.UNDELEGATION_FINALIZED,
            "Challenge period hasn't yet started"
        );

        // TODO: delete this if the slasher itself checks this?? (see TODO below -- might still have to check other addresses for consistency?)
        require(
            slasher.canSlash(
                operator,
                serviceFactory,
                repository,
                registrationManager
            ),
            "Contract does not have rights to prevent undelegation"
        );

        IServiceManager serviceManager = repository.serviceManager();

        // ongoing serviceObject is still active at time when staker was finalizing undelegation
        // and, therefore, hasn't served its obligation.
        require(
            lastUndelegationCommit[staker] >
                serviceManager.getServiceObjectCreationTime(
                    serviceObjectHash
                ) &&
                lastUndelegationCommit[staker] <
                serviceManager.getServiceObjectExpiry(serviceObjectHash),
            "serviceObject does not meet requirements"
        );

        //TODO: slash here
    }

    /// @notice checks whether a staker is currently undelegated and not
    ///         within challenge period from its last undelegation.
    function isNotDelegated(address staker) public view returns (bool) {
        // CRITIC: if delegation[staker] is set to address(0) during commitUndelegation,
        //         we can probably remove "(delegation[staker] == address(0)"
        return
            delegated[staker] == DelegationStatus.UNDELEGATED ||
            (delegated[staker] == DelegationStatus.UNDELEGATION_FINALIZED &&
                block.timestamp >
                undelegationFraudProofInterval +
                    lastUndelegationCommit[staker]);
    }

    /// @notice returns the delegationTerms for the input operator
    function getDelegationTerms(address operator)
        public
        view
        returns (IDelegationTerms)
    {
        return delegationTerms[operator];
    }

    /// @notice returns the strategies that are being used by the delegators of this operator
    function getOperatorStrats(address operator)
        public
        view
        returns (IInvestmentStrategy[] memory)
    {
        return operatorStrats[operator];
    }

    /**
     * @notice returns the shares in a specified strategy being used by the delegator of this operator
     **/

    function getOperatorShares(
        address operator,
        IInvestmentStrategy investmentStrategy
    ) public view returns (uint256) {
        return operatorShares[operator][investmentStrategy];
    }

    /**
     * @notice Returns the investment strategies, corresponding shares and the total ETH
     *         deposited with the operator.
     */
    function getControlledEthStake(address operator)
        external
        view
        returns (
            IInvestmentStrategy[] memory,
            uint256[] memory
        )
    {
        if (delegation[operator] == operator) {
            /**
             * @dev Under scenario where a delegator has delegated its asset to itself and
             * acting as its own operator. This would be because the staker called
             * delegateToSelf() for delegating its stake to itself.
             */
            (
                IInvestmentStrategy[] memory strats,
                uint256[] memory shares,
            ) = investmentManager.getDeposits(operator);
            return (strats, shares);
        } else {
            /**
             * @dev Under scenario where operator is being delegated assets by delegators.
             */
            // CRITIC: we are assuming here that delegation[operator] != operator which would
            // imply that operator is not actually an operator. Should there be a condition to check
            // whether operator is actually an operator or not? Like calling getOperatorType() in
            // Repository.sol and check it is non-zero?
            uint256[] memory shares = new uint256[](
                operatorStrats[operator].length
            );
            for (uint256 i = 0; i < shares.length; i++) {
                shares[i] = operatorShares[operator][
                    operatorStrats[operator][i]
                ];
            }
            return (operatorStrats[operator], shares);
        }
    }

    /// @notice Returns the total ETH value of the shares that have been deposited by the
    //          delegators with operator while using investment strategies
    function getUnderlyingEthDelegated(address operator)
        external
        returns (uint256)
    {
        uint256 weight;

        if (delegation[operator] == operator) {
            // when the operator has delegated to self

            //  get all strategies
            IInvestmentStrategy[] memory investorStrats = investmentManager
                .getStrategies(operator);

            //  get shares of all strategies
            uint256[] memory investorShares = investmentManager
                .getStrategyShares(operator);

            // get cumulative ETH value of all shares
            for (uint256 i = 0; i < investorStrats.length; ) {
                weight += investorStrats[i].underlyingEthValueOfShares(
                    investorShares[i]
                );
                unchecked {
                    ++i;
                }
            }
        } else {
            // when the operator hasn't delegated to itself but other stakers
            // have delegated
            // CRITIC: same problem as in getControlledEthStake, with calling
            // operatorStrats[operator] for the case "delegation[operator] != operator"

            // get all the investment strategies that is being used by any delegator
            IInvestmentStrategy[] memory investorStrats = operatorStrats[
                operator
            ];

            // get cumulative ETH value of all shares
            for (uint256 i = 0; i < investorStrats.length; ) {
                weight += investorStrats[i].underlyingEthValueOfShares(
                    operatorShares[operator][investorStrats[i]]
                );
                unchecked {
                    ++i;
                }
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
            for (uint256 i = 0; i < investorStrats.length; ) {
                weight += investorStrats[i].underlyingEthValueOfSharesView(
                    investorShares[i]
                );
                unchecked {
                    ++i;
                }
            }
        } else {
            // CRITIC: same problem as in getControlledEthStake, with calling
            // operatorStrats[operator] for the case "delegation[operator] != operator"
            IInvestmentStrategy[] memory investorStrats = operatorStrats[
                operator
            ];
            for (uint256 i = 0; i < investorStrats.length; ) {
                weight += investorStrats[i].underlyingEthValueOfSharesView(
                    operatorShares[operator][investorStrats[i]]
                );
                unchecked {
                    ++i;
                }
            }
        }
        return weight;
    }

    /// @notice returns the total ETH delegated by delegators with this operator
    ///         while staking it with the settlement layer (beacon chain)
    // CRITIC: change name to getSettlementLayerEthDelegated
    function getConsensusLayerEthDelegated(address operator)
        external
        view
        returns (uint256)
    {
        // CRITIC: same problem as in getControlledEthStake, with calling
        // operatorStrats[operator] for the case "delegation[operator] != operator"
        return
            delegation[operator] == operator
                ? investmentManager.getConsensusLayerEth(operator)
                : operatorShares[operator][investmentManager.consensusLayerEthStrat()];
    }

    /// @notice returns the total Eigen delegated by delegators with this operator
    function getEigenDelegated(address operator)
        external
        view
        returns (uint256)
    {
        // CRITIC: same problem as in getControlledEthStake, with calling
        // operatorStrats[operator] for the case "delegation[operator] != operator
        return
            delegation[operator] == operator
                ? investmentManager.getEigen(operator)
                : eigenDelegated[operator];
    }

    function isDelegatedToSelf(address operator)
        external
        view
        returns (bool)
    {
        return (delegation[operator] == operator);
    }
}
