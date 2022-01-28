// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.11;

import "./interfaces/IOperatorPermitter.sol";
import "./utils/SafeERC20.sol";

contract ServiceRegistry {
	using SafeERC20 for address;
	address public immutable MASTER_REGISTRY;
	address public immutable PAYMENT_TOKEN;
	uint256 internal constant REWARD_SCALING = 2**64;
	uint16 internal constant MAX_BIPS = 10000;

	//controls whether addresses can register as operators or not
	address public operatorPermitter;
	//sum of all stakes
	uint256 public totalStakes;
	//scaled up by 'REWARD_SCALING'
	uint256 public paymentPerStake;
	//stake of each user
	mapping(address => uint256) public stakes;
	//mapping from user to delegatee
	mapping(address => address) public delegates;
	//mapping from keep track of delegator rewards already claimed
	mapping(address => uint256) public operatorEarningsPerStakeAtLastUpdate;
	//whether or not each address is a registered operator
	mapping(address => bool) public registeredOperators;
	//mapping from registered operators to their amount of delegated stake
	mapping(address => uint256) public delegatedStakes;
	//mapping to keep track of delegatee rewards already claimed
	mapping(address => uint256) public paymentPerStakeAtLastUpdate;
	//mapping to keep track of how much each operator has earned per stake, scaled up by 'REWARD_SCALING'
	mapping(address => uint256) public operatorEarningsPerStake;

	//mapping to keep track of amount of earnings kept by operator (in BIPs, i.e. parts in 10,000)
	mapping(address => uint16) public operatorFeeBips;
	//mapping to keep track of unwithdrawn operator earnings. not scaled.
	mapping(address => uint256) public operatorPendingEarnings;

    /// @notice Emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    /// @notice Emitted when a delegate's balance of delegated stake changes
    event DelegateStakeChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
    /// @notice Emitted when an operator claims their rewards
    event ClaimedForOperator(address indexed operator, uint256 paymentAmount);
    /// @notice Emitted when a delegator claims their rewards
    event ClaimedForDelegator(address indexed delegator, uint256 paymentAmount);
    /// @notice Emitted when an account's stake is updated
    event StakeUpdated(address indexed delegator, uint256 previousStakeAmount, uint256 newStakeAmount);

    event OperatorRegistered(address indexed operator);
    event OperatorUnregistered(address indexed operator);
    event OperatorPermitterSet(address indexed previousAddress, address indexed newAddress);
    event OperatorFeeBipsSet(address indexed operator, uint256 oldFeeValue, uint256 newFeeValue);

    modifier onlyMasterRegistry() {
    	require(msg.sender == MASTER_REGISTRY, "onlyMasterRegistry");
    	_;
    }

	constructor(address _MASTER_REGISTRY, address _PAYMENT_TOKEN, address _operatorPermitter) {
		MASTER_REGISTRY = _MASTER_REGISTRY;
		PAYMENT_TOKEN = _PAYMENT_TOKEN;
		operatorPermitter = _operatorPermitter;
		OperatorPermitterSet(address(0), _operatorPermitter);
	}

	function updateStake(address delegator, uint256 newStakeAmount) external onlyMasterRegistry {
        address currentDelegate = delegates[delegator];
        if (currentDelegate != address(0)){
        	//update any pending rewards for the existing delegatee and for the new delegatee
	        _claimForDelegatee(currentDelegate);
	        //claim any pending rewards for the delegator
	        _claimForDelegator(delegator);
	        emit DelegateStakeChanged(currentDelegate, currentDelegateBalance, delegatedStakes[currentDelegate]);
        	//update delegator rewards tracking info, so they do not earn rewards they are not entitled to
        	operatorEarningsPerStakeAtLastUpdate[delegator] = operatorEarningsPerStake[delegatee];
        	//adjust total stakes, but only if delegator has already delegated. avoids paying out for undelegated stakes.
        	totalStakes = (totalStakes + newStakeAmount) - stakes[delegator];
        }
		emit StakeUpdated(delegator, stakes[delegator], newStakeAmount);
        stakes[delegator] = newStakeAmount;
	}

	function setOperatorPermitter(address _operatorPermitter) external onlyMasterRegistry {
		require(_operatorPermitter != address(0), "zero addr bad");
		OperatorPermitterSet(operatorPermitter, _operatorPermitter);
		operatorPermitter = _operatorPermitter;
	}

	function registerOperator(address operator) external {
		require(IOperatorPermitter(operatorPermitter).operatorPermitted(operator), "operator does not meet requirements");
		registeredOperators[operator] = true;
		emit OperatorRegistered(operator);
	}

	function setOperatorFeeBips(uint256 bips) external {
		require(bips <= MAX_BIPS, "setOperatorFeeBips: input too high");
		_claimForDelegatee(msg.sender);
		OperatorFeeBipsSet(msg.sender, operatorFeeBips[msg.sender], bips);
		operatorFeeBips[msg.sender] = bips;
	}

	//TODO: figure out what to do with operator's delegates!
	function unregisterOperator(address operator) external {
		require(!IOperatorPermitter(operatorPermitter).operatorPermitted(operator), "operator still meets requirements");
		registeredOperators[operator] = false;
		emit OperatorUnregistered(operator);
	}

	function makePayment(uint256 amount) external {
    	paymentPerStake += ((amount * REWARD_SCALING) / totalStakes);
    	_safeTransferFrom(PAYMENT_TOKEN, msg.sender, address(this), amount);
	}

    function operatorWithdrawal(address operator) external {
    	uint256 paymentAmount = operatorPendingEarnings[operator];
    	operatorPendingEarnings[operator] = 0;
    	_safeTransfer(PAYMENT_TOKEN, operator, paymentAmount);
    	emit ClaimedForOperator(operator, paymentAmount);
    }

  	/**
    * @notice Delegate votes from `msg.sender` to `delegatee`
    * @param delegatee The address to delegate votes to
    */
    function delegate(address delegatee) external {
		_delegate(msg.sender, delegatee);
    }

    function _delegate(address delegator, address delegatee) internal {
    	require(delegatee != address(0), "delegation to zero address forbidden");
    	require(registeredOperators[delegatee], "must delegate to a registered operator");
        address currentDelegate = delegates[delegator];
        uint256 delegatorBalance = stakes[delegator];
        uint256 currentDelegateBalance = delegatedStakes[currentDelegate];
        uint256 delegateeBalance = delegatedStakes[delegatee];
        if (currentDelegate != address(0)){
        	//update any pending rewards for the existing delegatee and for the new delegatee
	        _claimForDelegatee(currentDelegate);
	        _claimForDelegatee(delegatee);
	        //claim any pending rewards for the delegator
	        _claimForDelegator(delegator);
	        //decrease delegated stakes for old delegatee
	        delegatedStakes[currentDelegate] -= delegatorBalance;
	        emit DelegateStakeChanged(currentDelegate, currentDelegateBalance, delegatedStakes[currentDelegate]);
        } else {
        	//add to totalStakes in the event that the delegator is delegating for the first time
        	totalStakes += stakes[delegator];
        }
        //update delegator rewards tracking info, so they do not earn rewards they are not entitled to
        operatorEarningsPerStakeAtLastUpdate[delegator] = operatorEarningsPerStake[delegatee];
        //update delegate tracking 
        delegates[delegator] = delegatee;
        emit DelegateChanged(delegator, currentDelegate, delegatee);
        //increase delegated stakes for new delegatee
        delegatedStakes[delegatee] += delegatorBalance;
        emit DelegateStakeChanged(delegatee, delegateeBalance, delegatedStakes[delegatee]);
    }

    function _claimForDelegatee(address delegatee) internal {
        uint256 delegateeBalance = delegatedStakes[delegatee];
        if (delegateeBalance > 0) {
	    	uint256 newPaymentPerStake = paymentPerStake;
	    	uint256 gainInPaymentPerStake = (newPaymentPerStake - paymentPerStakeAtLastUpdate[delegatee]);
	    	if (gainInPaymentPerStake > 0) {
	    		paymentPerStakeAtLastUpdate[delegatee] = newPaymentPerStake;
	    		uint256 paymentAmount = (gainInPaymentPerStake * delegateeBalance) / REWARD_SCALING;
	    		operatorPendingEarnings += (paymentAmount * operatorFeeBips[delegatee]) / MAX_BIPS;
	    		operatorEarningsPerStake[delegatee] += (gainInPaymentPerStake * (MAX_BIPS - operatorFeeBips[delegatee])) / MAX_BIPS;
	    		paymentPerStakeAtLastUpdate[delegatee] = newPaymentPerStake;
	    	}
        }
    }

    //NOTE: MUST FIRST CLAIM FOR DELEGATEE TO FULLY REALIZE EARNINGS (NO MISSING EARNINGS IF DELEGATEE NOT CHANGING THOUGH, JUST DELAYED UNTIL LATER)
    function _claimForDelegator(address delegator) internal {
    	uint256 delegatorStakes = stakes[delegator];
    	if (delegatorStakes > 0) {
	        address currentDelegate = delegates[delegator];
		   	uint256 operatorEarningsPerStake = operatorEarningsPerStake[currentDelegate];
		   	uint256 gainInOperatorEarningsPerStake = operatorEarningsPerStake - operatorEarningsPerStakeAtLastUpdate[delegator];
		   	if (gainInOperatorEarningsPerStake > 0) {
		   		operatorEarningsPerStakeAtLastUpdate[delegator] = operatorEarningsPerStake;
		   		paymentAmount = (gainInOperatorEarningsPerStake * delegatorStakes) / REWARD_SCALING;
		    	_safeTransfer(PAYMENT_TOKEN, delegator, paymentAmount);
		    	emit ClaimedForDelegator(delegator, paymentAmount);
		   	}
    	}
    }
}





