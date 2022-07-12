// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "./EigenLayrDelegationStorage.sol";
import "../libraries/SignatureCompaction.sol";
import "../investment/Slasher.sol";

// TODO: updating of stored addresses by governance?
// TODO: verify that limitation on undelegating from slashed operators is sufficient

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
    OwnableUpgradeable,
    EigenLayrDelegationStorage
{
    modifier onlyInvestmentManager() {
        require(
            msg.sender == address(investmentManager),
            "onlyInvestmentManager"
        );
        _;
    }

    constructor() {
        // TODO: uncomment for production use!
        //_disableInitializers();
    }

    event OnDelegationWithdrawnCallFailure(IDelegationTerms indexed delegationTerms, bytes returnData);

    function initialize(
        IInvestmentManager _investmentManager,
        uint256 _undelegationFraudProofInterval
    ) external initializer {
        require(_undelegationFraudProofInterval <= MAX_UNDELEGATION_FRAUD_PROOF_INTERVAL);
        investmentManager = _investmentManager;
        undelegationFraudProofInterval = _undelegationFraudProofInterval;
        _transferOwnership(msg.sender);
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
        _delegate(msg.sender, msg.sender);
    }

    /// @notice This will be called by a staker if it wants to act as its own operator.
    function delegateToSelf() external {
        require(
            address(delegationTerms[msg.sender]) == address(0),
            "delegateToSelf: Delegate has already registered"
        );
        require(
            isNotDelegated(msg.sender),
            "delegateToSelf: Staker has existing delegation or pending undelegation commitment"
        );
        // store delegation relation that the staker (msg.sender) is its own operator
        delegation[msg.sender] = SELF_DELEGATION_ADDRESS;
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
            nonces[delegator] == nonce,
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
        ++nonces[delegator];
        _delegate(delegator, operator);
    }

    // internal function implementing the delegation of 'delegator' to 'operator'
    function _delegate(address delegator, address operator) internal {
        IDelegationTerms dt = delegationTerms[operator];
        require(
            address(dt) != address(0),
            "_delegate: operator has not registered as a delegate yet. Please call registerAsDelegate(IDelegationTerms dt) first."
        );
        require(
            isNotDelegated(delegator),
            "_delegate: delegator has existing delegation"
        );
        // checks that operator has not been slashed
        require(!investmentManager.slashedStatus(operator),
            "cannot delegate to a slashed operator"
        );

        // record delegation relation between the delegator and operator
        delegation[delegator] = operator;

        // record that the staker is delegated
        delegated[delegator] = DelegationStatus.DELEGATED;

        // retrieve list of strategies and their shares from investment manager
        (
            IInvestmentStrategy[] memory strategies,
            uint256[] memory shares
        ) = investmentManager.getDeposits(delegator);

        // add strategy shares to delegate's shares
        uint256 stratsLength = strategies.length;
        for (uint256 i = 0; i < stratsLength;) {
            // update the total share deposited in favor of the strategy in the operator's portfolio
            operatorShares[operator][strategies[i]] += shares[i];
            unchecked {
                ++i;
            }
        }

        // call into hook in delegationTerms contract
        dt.onDelegationReceived(
                delegator,
                strategies,
                shares
        );
    }

    /// @notice This function is used to notify the system that a delegator wants to stop
    ///         participating in the functioning of EigenLayr.

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
    function commitUndelegation() external {
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
        if (operator != SELF_DELEGATION_ADDRESS) {
            // checks that operator has not been slashed
            require(!investmentManager.slashedStatus(operator),
                "operator has been slashed. must wait for resolution before undelegation"
            );

            // retrieve list of strategies and their shares from investment manager
            (
                IInvestmentStrategy[] memory strategies,
                uint256[] memory shares
            ) = investmentManager.getDeposits(msg.sender);
            // remove strategy shares from delegate's shares
            uint256 stratsLength = strategies.length;
            for (uint256 i = 0; i < stratsLength;) {
                // update the total share deposited in favor of the strategy in the operator's portfolio
                operatorShares[operator][strategies[i]] -= shares[i];
                unchecked {
                    ++i;
                }
            }

            // set that they are no longer delegated to anyone
            delegated[msg.sender] = DelegationStatus.UNDELEGATION_COMMITTED;

            // call into hook in delegationTerms contract
            // we use low-level call functionality here to ensure that an operator cannot maliciously make this function fail in order to prevent undelegation
            // TODO: do we also need a max gas budget to avoid griefing here?
            (bool success, bytes memory returnData) = address(delegationTerms[operator]).call(
                abi.encodeWithSelector(
                    IDelegationTerms.onDelegationWithdrawn.selector,
                    msg.sender,
                    strategies,
                    shares    
                )            
            );
            // if the internal call fails, we emit a special event rather than reverting
            if (!success) {
                emit OnDelegationWithdrawnCallFailure(delegationTerms[operator], returnData);
            }
        } else {
            // checks that operator has not been slashed
            require(!investmentManager.slashedStatus(msg.sender),
                "operator has been slashed. must wait for resolution before undelegation"
            );
            delegated[msg.sender] = DelegationStatus.UNDELEGATION_COMMITTED;
        }
    }

    function decreaseOperatorShares(
        address operator,
        IInvestmentStrategy strategy,
        uint256 shares
    ) external onlyInvestmentManager {
        // subtract strategy shares from delegate's shares
        operatorShares[operator][strategy] -= shares;
    }

    function decreaseOperatorShares(
        address operator,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata shares
    ) external onlyInvestmentManager {
        // subtract strategy shares from delegate's shares
        uint256 stratsLength = strategies.length;
        for (uint256 i = 0; i < stratsLength;) {
            operatorShares[operator][strategies[i]] -= shares[i];
            unchecked {
                ++i;
            }
        }
    }

    function increaseOperatorShares(
        address operator,
        IInvestmentStrategy strategy,
        uint256 shares
    ) external onlyInvestmentManager {
        // add strategy shares to delegate's shares
        operatorShares[operator][strategy] += shares;
     }

    function increaseOperatorShares(
        address operator,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata shares
    ) external onlyInvestmentManager {
        // add strategy shares to delegate's shares
        uint256 stratsLength = strategies.length;
        for (uint256 i = 0; i < stratsLength;) {
            operatorShares[operator][strategies[i]] += shares[i];
            unchecked {
                ++i;
            }
        }
    }

    /// @notice This function must be called by a delegator to notify that its stake is
    ///         no longer active on any queries, which in turn launches the challenge period.
    function finalizeUndelegation() external {
        require(
            delegated[msg.sender] == DelegationStatus.UNDELEGATION_COMMITTED,
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
    /// @param staker is the delegator against whom challenge is being raised
    function contestUndelegationCommit(
        address staker,
        bytes calldata data,
        IServiceFactory serviceFactory,
        IRepository repository,
        IRegistry registry
    ) external {
        require(
            block.timestamp <
                undelegationFraudProofInterval + lastUndelegationCommit[staker],
            "Challenge was raised after the end of challenge period"
        );

        require(
            delegated[staker] == DelegationStatus.UNDELEGATION_FINALIZED,
            "Challenge period hasn't yet started"
        );

        ISlasher slasher = investmentManager.slasher();

        // TODO: delete this if the slasher itself checks this?? (see TODO below -- might still have to check other addresses for consistency?)
        require(
            slasher.canSlash(
                delegation[staker],
                serviceFactory,
                repository,
                registry
            ),
            "Contract does not have rights to prevent undelegation"
        );

    // scoped block to help solve stack too deep
    {
        IServiceManager serviceManager = repository.serviceManager();

        // ongoing task is still active at time when staker was finalizing undelegation
        // and, therefore, hasn't served its obligation.
        serviceManager.stakeWithdrawalVerification(data, lastUndelegationCommit[staker], lastUndelegationCommit[staker]);
    }

        // perform the slashing itself
        slasher.slashOperator(staker); 

        // TODO: reset status of staker to having not committed to de-delegation?
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

    /**
     * @notice returns the shares in a specified strategy either held directly by or delegated to the operator
     **/

    function getOperatorShares(
        address operator,
        IInvestmentStrategy investmentStrategy
    ) public view returns (uint256) {
        return
            isSelfOperator(operator)
                ? investmentManager.investorStratShares(operator, investmentStrategy)
                : operatorShares[operator][investmentStrategy];
    }

    function isSelfOperator(address operator)
        public
        view
        returns (bool)
    {
        return (delegation[operator] == SELF_DELEGATION_ADDRESS);
    }

    function isDelegator(address staker)
        public
        view
        returns (bool)
    {
        address delegatedAddress = delegation[staker];
        return (delegatedAddress != address(0) && delegatedAddress != SELF_DELEGATION_ADDRESS);
    }

    function setInvestmentManager(IInvestmentManager _investmentManager) external onlyOwner {
        investmentManager = _investmentManager;
    }

    function setUndelegationFraudProofInterval(uint256 _undelegationFraudProofInterval) external onlyOwner {
        require(_undelegationFraudProofInterval <= MAX_UNDELEGATION_FRAUD_PROOF_INTERVAL);
        undelegationFraudProofInterval = _undelegationFraudProofInterval;
    }
}
