
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

    // external calls to EigenPod (from EigenPodManager)
    withdrawRestakedBeaconChainETH(address, uint256) => DISPATCHER(true)
	    
    // external calls to IDelegationTerms
    onDelegationWithdrawn(address,address[],uint256[]) => CONSTANT
    onDelegationReceived(address,address[],uint256[]) => CONSTANT
    
    // external calls to PauserRegistry
    pauser() returns (address) => DISPATCHER(true)
	unpauser() returns (address) => DISPATCHER(true)

    // external calls to ERC20
    transfer(address, uint256) returns (bool) => DISPATCHER(true)
    transferFrom(address, address, uint256) returns (bool) => DISPATCHER(true)
	
    //// Harnessed Functions
    // Harnessed calls
    // Harnessed getters
    strategy_is_in_stakers_array(address, address) returns (bool) envfree
    num_times_strategy_is_in_stakers_array(address, address) returns (uint256) envfree

	//// Normal Functions
	investorStratsLength(address) returns (uint256) envfree
    investorStrats(address, uint256) returns (address) envfree
    investorStratShares(address, address) returns (uint256) envfree
    array_exhibits_properties(address) returns (bool) envfree
}

invariant investorStratsLengthLessThanOrEqualToMax(address staker)
	investorStratsLength(staker) <= 32

// verifies that strategies in the staker's array of strategies are not duplicated, and that the staker has nonzero shares in each one
invariant arrayExhibitsProperties(address staker)
    array_exhibits_properties(staker) == true
        {
            preserved
            {
                requireInvariant investorStratsLengthLessThanOrEqualToMax(staker);
            }
        }

// if a strategy is *not* in staker's array of strategies, then the staker should have precisely zero shares in that strategy
invariant strategiesNotInArrayHaveZeroShares(address staker, uint256 index)
    (index >= investorStratsLength(staker)) => (investorStratShares(staker, investorStrats(staker, index)) == 0)