// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./EigenLayrDelegationStorage.sol";
import "../investment/Slasher.sol";

import "forge-std/Test.sol";

// TODO: updating of stored addresses by governance?
// TODO: verify that limitation on undelegating from slashed operators is sufficient

/**
 * @notice  This is the contract for delegation in EigenLayr. The main functionalities of this contract are
 *            - for enabling any staker to register as a delegate and specify the delegation terms it has agreed to
 *            - for enabling anyone to register as an operator
 *            - for a registered staker to delegate its stake to the operator of its agreed upon delegation terms contract
 *            - for a staker to undelegate its assets from EigenLayr
 *            - for anyone to challenge a staker's claim to have fulfilled all its obligation before undelegation
 */
contract EigenLayrDelegation is
    Initializable,
    OwnableUpgradeable,
    EigenLayrDelegationStorage,
    DSTest
{
    modifier onlyInvestmentManager() {
        require(
            msg.sender == address(investmentManager),
            "onlyInvestmentManager"
        );
        _;
    }

    // INITIALIZING FUNCTIONS
    constructor() {
        // TODO: uncomment for production use!
        //_disableInitializers();
    }

    /**
     * @dev Emitted when a low-level call to `delegationTerms.onDelegationReceived` fails, returning `returnData`
     */
    event OnDelegationReceivedCallFailure(IDelegationTerms indexed delegationTerms, bytes returnData);
    /**
     * @dev Emitted when a low-level call to `delegationTerms.onDelegationWithdrawn` fails, returning `returnData`
     */
    event OnDelegationWithdrawnCallFailure(IDelegationTerms indexed delegationTerms, bytes returnData);

    // sets the `investMentManager` address (**currently modifiable by contract owner -- see below**)
    // sets the `undelegationFraudProofInterval` value (**currently modifiable by contract owner -- see below**)
    // transfers ownership to `msg.sender`
    function initialize(
        IInvestmentManager _investmentManager,
        uint256 _undelegationFraudProofInterval
    ) external initializer {
        require(_undelegationFraudProofInterval <= MAX_UNDELEGATION_FRAUD_PROOF_INTERVAL);
        investmentManager = _investmentManager;
        undelegationFraudProofInterval = _undelegationFraudProofInterval;
        _transferOwnership(msg.sender);
    }

    // EXTERNAL FUNCTIONS

    /// @notice This will be called by an operator to register itself as a delegate that stakers
    ///         can choose to delegate to.
    /// @param dt is the delegation terms contract that operator has for those who delegate to them.
    function registerAsDelegate(IDelegationTerms dt) external {
        require(
            address(delegationTerms[msg.sender]) == address(0),
            "EigenLayrDelegation.registerAsDelegate: Delegate has already registered"
        );
        // store the address of the delegation contract that operator is providing.
        delegationTerms[msg.sender] = dt;
        _delegate(msg.sender, msg.sender);
    }

    /// @notice This will be called by a staker to delegate its assets to some operator
    /// @param operator is the operator to whom staker (msg.sender) is delegating its assets
    function delegateTo(address operator) external {
        _delegate(msg.sender, operator);
    }

    // delegates from `staker` to `operator`
    // requires that r, vs are a valid ECSDA signature from `staker` indicating their intention for this action
    function delegateToBySignature(
        address staker,
        address operator,
        uint256 expiry,
        bytes32 r,
        bytes32 vs
    ) external {
        require(
            expiry == 0 || expiry >= block.timestamp,
            "delegation signature expired"
        );
        // calculate struct hash, then increment `staker`'s nonce
        bytes32 structHash = keccak256(
            abi.encode(DELEGATION_TYPEHASH, staker, operator, nonces[staker]++, expiry)
        );
        bytes32 digestHash = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );
        //check validity of signature
        address recoveredAddress = ECDSA.recover(
            digestHash,
            r,
            vs
        );
        require(
            recoveredAddress == staker,
            "EigenLayrDelegation.delegateToBySignature: sig not from staker"
        );
        _delegate(staker, operator);
    }

    /// @notice This function is used to notify the system that a staker wants to stop
    ///         participating in the functioning of EigenLayr.
    function initUndelegation() external {
        require(
            isDelegated(msg.sender),
            "EigenLayrDelegation.initUndelegation: Staker does not have existing delegation"
        );

        // get the current operator for the staker (msg.sender)
        address operator = delegation[msg.sender];
        // checks that operator has not been frozen
        ISlasher slasher = investmentManager.slasher();
        require(!slasher.frozenStatus(operator),
            "EigenLayrDelegation.initUndelegation: operator has been frozen. must wait for resolution before undelegation"
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

        // call into hook in delegationTerms contract
        IDelegationTerms dt = delegationTerms[operator];
        _delegationWithdrawnHook(dt, msg.sender, strategies, shares);

        // store the time at which the staker began undelegation
        undelegationInitTime[msg.sender] = block.timestamp;

        // set that the staker has begun the undelegation process, i.e. "initialized" it
        delegated[msg.sender] = DelegationStatus.UNDELEGATION_INITIALIZED;
    }

    /// @notice This function must be called by a staker to notify that its stake is
    ///         no longer active on any queries, which in turn launches the challenge period.
    function commitUndelegation() external {
        require(
            delegated[msg.sender] == DelegationStatus.UNDELEGATION_INITIALIZED,
            "EigenLayrDelegation.finalizeUndelegation: Staker is not in the post commit phase"
        );

        // set time of undelegation finalization which is the end of the corresponding challenge period
        undelegationFinalizedTime[msg.sender] = block.timestamp + undelegationFraudProofInterval; 

        // set that the staker has committed to undelegating
        delegated[msg.sender] = DelegationStatus.UNDELEGATION_COMMITTED;

        address operator = delegation[msg.sender];
        (
            IInvestmentStrategy[] memory strategies,
            uint256[] memory shares
        ) = investmentManager.getDeposits(msg.sender);


        
    }

    /// @notice This function can be called by anyone to challenge whether a staker has
    ///         finalized its undelegation after satisfying its obligations in EigenLayr or not.
    /// @param staker is the staker against whom challenge is being raised
    function contestUndelegationCommit(
        address staker,
        bytes calldata data,
        IServiceManager slashingContract
    ) external {
        require(
            delegated[staker] == DelegationStatus.UNDELEGATION_COMMITTED,
            "EigenLayrDelegation.contestUndelegationCommit: Challenge period hasn't yet started"
        );

        require(
            block.timestamp < undelegationFinalizedTime[staker],
            "EigenLayrDelegation.contestUndelegationCommit: Challenge was raised after the end of challenge period"
        );

        ISlasher slasher = investmentManager.slasher();
        // TODO: delete this if the slasher itself checks this?? (see TODO below -- might still have to check other addresses for consistency?)
        require(
            slasher.canSlash(
                delegation[staker],
                address(slashingContract)
            ),
            "EigenLayrDelegation.contestUndelegationCommit: Contract does not have rights to prevent undelegation"
        );

    // scoped block to help solve stack too deep
    {
        // verify that ongoing task is still active and began before staker initiated their undelegation, proving that staker hasn't fully served its obligation yet
        slashingContract.stakeWithdrawalVerification(data, undelegationInitTime[staker], block.timestamp);
    }

        // perform the slashing itself
        slasher.freezeOperator(staker); 

        // reset status of staker to having committed to undelegation but not yet finalized
        delegated[msg.sender] = DelegationStatus.UNDELEGATION_INITIALIZED;
    }

    //increases a stakers delegated shares to a certain strategy, usually whenever they have further deposits into EigenLayr
    function increaseDelegatedShares(address staker, IInvestmentStrategy strategy, uint256 shares) external onlyInvestmentManager {
        //if the staker is delegated to an operator
        if(isDelegated(staker)) {
            address operator = delegation[staker];
            // add strategy shares to delegate's shares
            operatorShares[operator][strategy] += shares;

            //Calls into operator's delegationTerms contract to update weights of individual staker
            IInvestmentStrategy[] memory investorStrats = new IInvestmentStrategy[](1);
            uint[] memory investorShares = new uint[](1);
            investorStrats[0] = strategy;
            investorShares[0] = shares;

            // call into hook in delegationTerms contract
            IDelegationTerms dt = delegationTerms[operator];
            _delegationReceivedHook(dt, staker, investorStrats, investorShares);
        }
    }

    //decreases a stakers delegated shares to a certain strategy, usually whenever they withdraw from EigenLayr
    function decreaseDelegatedShares(address staker, IInvestmentStrategy strategy, uint256 shares) external onlyInvestmentManager {
        //if the staker is delegated to an operator
        if(isDelegated(staker)) {
            address operator = delegation[staker];

            // subtract strategy shares from delegate's shares
            operatorShares[operator][strategy] -= shares;

            //Calls into operator's delegationTerms contract to update weights of individual staker
            IInvestmentStrategy[] memory investorStrats = new IInvestmentStrategy[](1);
            uint[] memory investorShares = new uint[](1);
            investorStrats[0] = strategy;
            investorShares[0] = shares;

            // call into hook in delegationTerms contract
            IDelegationTerms dt = delegationTerms[operator];
            _delegationWithdrawnHook(dt, staker, investorStrats, investorShares);
        }
    }

    function decreaseDelegatedShares(
        address staker,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata shares
    ) external onlyInvestmentManager {
        if(isDelegated(staker)) {
            address operator = delegation[staker];

            // subtract strategy shares from delegate's shares
            uint256 stratsLength = strategies.length;
            for (uint256 i = 0; i < stratsLength;) {
                operatorShares[operator][strategies[i]] -= shares[i];
                unchecked {
                    ++i;
                }
            }

            // call into hook in delegationTerms contract
            IDelegationTerms dt = delegationTerms[operator];
            _delegationWithdrawnHook(dt, staker, strategies, shares);
        }
    }

    function setInvestmentManager(IInvestmentManager _investmentManager) external onlyOwner {
        investmentManager = _investmentManager;
    }

    function setUndelegationFraudProofInterval(uint256 _undelegationFraudProofInterval) external onlyOwner {
        require(_undelegationFraudProofInterval <= MAX_UNDELEGATION_FRAUD_PROOF_INTERVAL);
        undelegationFraudProofInterval = _undelegationFraudProofInterval;
    }

    // INTERNAL FUNCTIONS

    function _delegationReceivedHook(IDelegationTerms dt, address staker, IInvestmentStrategy[] memory strategies, uint256[] memory shares) internal {
        // we use low-level call functionality here to ensure that an operator cannot maliciously make this function fail in order to prevent undelegation
        (bool success, bytes memory returnData) = address(dt).call{gas: LOW_LEVEL_GAS_BUDGET}(
            abi.encodeWithSelector(
                IDelegationTerms.onDelegationReceived.selector,
                staker,
                strategies,
                shares
            )
        );
        // if the internal call fails, we emit a special event rather than reverting
        if (!success) {
            emit OnDelegationReceivedCallFailure(dt, returnData);
        }
    }

    function _delegationWithdrawnHook(IDelegationTerms dt, address staker, IInvestmentStrategy[] memory strategies, uint256[] memory shares) internal {
        // we use low-level call functionality here to ensure that an operator cannot maliciously make this function fail in order to prevent undelegation
        (bool success, bytes memory returnData) = address(dt).call{gas: LOW_LEVEL_GAS_BUDGET}(
            abi.encodeWithSelector(
                IDelegationTerms.onDelegationWithdrawn.selector,
                staker,
                strategies,
                shares    
            )            
        );
        // if the internal call fails, we emit a special event rather than reverting
        if (!success) {
            emit OnDelegationWithdrawnCallFailure(dt, returnData);
        }
    }

    // internal function implementing the delegation of 'staker' to 'operator'
    function _delegate(address staker, address operator) internal {
        IDelegationTerms dt = delegationTerms[operator];
        require(
            address(dt) != address(0),
            "EigenLayrDelegation._delegate: operator has not registered as a delegate yet. Please call registerAsDelegate(IDelegationTerms dt) first"
        );

        require(
            isNotDelegated(staker),
            "EigenLayrDelegation._delegate: staker has existing delegation"
        );
        // checks that operator has not been frozen
        ISlasher slasher = investmentManager.slasher();
        require(!slasher.frozenStatus(operator),
            "EigenLayrDelegation._delegate: cannot delegate to a frozen operator"
        );

        // record delegation relation between the staker and operator
        delegation[staker] = operator;

        // record that the staker is delegated
        delegated[staker] = DelegationStatus.DELEGATED;

        // retrieve list of strategies and their shares from investment manager
        (
            IInvestmentStrategy[] memory strategies,
            uint256[] memory shares
        ) = investmentManager.getDeposits(staker);

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
        _delegationReceivedHook(dt, staker, strategies, shares);
    }

    // VIEW FUNCTIONS

    /// @notice checks whether a staker is currently undelegated OR has committed to undelegation
    ///         and is not within the challenge period for its last undelegation.
    function isNotDelegated(address staker) public returns (bool) {

        return
        
            delegated[staker] == DelegationStatus.UNDELEGATED ||
            (delegated[staker] == DelegationStatus.UNDELEGATION_COMMITTED &&
                block.timestamp > undelegationFinalizedTime[staker]);
    }

    function isDelegated(address staker)
        public
        view
        returns (bool)
    {
        return (delegated[staker] == DelegationStatus.DELEGATED);
    }

    //returns if an operator can be delegated to, i.e. it has a delegation terms
    function isDelegate(address operator)
        public
        view
        returns(bool)
    {
        return(address(delegationTerms[operator]) != address(0));
    }
}