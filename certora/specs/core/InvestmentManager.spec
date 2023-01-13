
methods {
    //// External Calls
	// external calls to EigenLayerDelegation 
    undelegate(address) => DISPATCHER(true)
    isDelegated(address) returns (bool) => DISPATCHER(true)
    delegatedTo(address) returns (address) => DISPATCHER(true)
	decreaseDelegatedShares(address,address[],uint256[]) => DISPATCHER(true)
	increaseDelegatedShares(address,address,uint256) => DISPATCHER(true)
	_delegationReceivedHook(address,address,address[],uint256[]) => NONDET
    _delegationWithdrawnHook(address,address,address[],uint256[]) => NONDET

	// external calls to Slasher
    isFrozen(address) returns (bool) => DISPATCHER(true)
	canWithdraw(address,uint32,uint256) returns (bool) => DISPATCHER(true)

	// external calls to InvestmentManager
    getDeposits(address) returns (address[],uint256[]) => DISPATCHER(true)
    slasher() returns (address) => DISPATCHER(true)
	deposit(address,uint256) returns (uint256) => DISPATCHER(true)
	withdraw(address,address,uint256) => DISPATCHER(true)

	// external calls to EigenPodManager
	withdrawRestakedBeaconChainETH(address,address,uint256) => DISPATCHER(true)
	    
    // external calls to IDelegationTerms
    onDelegationWithdrawn(address,address[],uint256[]) => CONSTANT
    onDelegationReceived(address,address[],uint256[]) => CONSTANT
    
    // external calls to PauserRegistry
    pauser() returns (address) => DISPATCHER(true)
	unpauser() returns (address) => DISPATCHER(true)
	
    //// Harnessed Functions
    // Harnessed calls
    // Harnessed getters
    strategy_is_in_stakers_array(address, address) returns (bool) envfree

	//// Normal Functions
	investorStratsLength(address) returns (uint256) envfree
    investorStrats(address, uint256) returns (address) envfree
    investorStratShares(address, address) returns (uint256) envfree
}

invariant investorStratsLengthLessThanOrEqualToMax(address staker)
	investorStratsLength(staker) <= 32

// Seems like perhaps `strategiesInArrayHaveNonzeroShares` and `strategiesInArrayHaveNonzeroSharesAttemptTwo`
// are failing due to dispatcher hitting HAVOC inside of the safeTransfer of the Base Strategy (or similar, multi-level-deep calls)
// seeing failures in `queueWithdrawal`, `recordOvercommittedBeaconChainETH`, `completeQueuedWithdrawal`, `slashShares`, and `slashQueuedWithdrawal`

// TODO: this rule is currently failing, but is likely salvageable. presumably needs a stricter condition.
// if a strategy is in the staker's array of strategies, then the staker should have nonzero shares in that strategy
invariant strategiesInArrayHaveNonzeroShares(address staker, uint256 index)
    (index < investorStratsLength(staker)) => (investorStratShares(staker, investorStrats(staker, index)) > 0)

// if a strategy is in the staker's array of strategies, then the staker should have nonzero shares in that strategy
invariant strategiesInArrayHaveNonzeroSharesAttemptTwo(address staker, address strategy)
    strategy_is_in_stakers_array(staker, strategy) <=> (investorStratShares(staker, strategy) > 0)

// if a strategy is *not* in staker's array of strategies, then the staker should have precisely zero shares in that strategy
invariant strategiesNotInArrayHaveZeroShares(address staker, uint256 index)
    (index >= investorStratsLength(staker)) => (investorStratShares(staker, investorStrats(staker, index)) == 0)
