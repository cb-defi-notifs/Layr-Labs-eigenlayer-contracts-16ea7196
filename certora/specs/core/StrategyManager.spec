
methods {
    //// External Calls
	// external calls to DelegationManager 
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

	// external calls to StrategyManager
    getDeposits(address) returns (address[],uint256[]) 
    slasher() returns (address) 
	deposit(address,uint256) returns (uint256) 
	withdraw(address,address,uint256) 

	// external calls to Strategy
    deposit(address, uint256) returns (uint256) => DISPATCHER(true)
    withdraw(address, address, uint256) => DISPATCHER(true)
    totalShares() => DISPATCHER(true)  

	// external calls to EigenPodManager
	withdrawRestakedBeaconChainETH(address,address,uint256) => DISPATCHER(true)

    // external calls to EigenPod (from EigenPodManager)
    withdrawRestakedBeaconChainETH(address, uint256) => DISPATCHER(true)
	    
    // external calls to DelayedWithdrawalRouter (from EigenPod)
    createDelayedWithdrawal(address, address) => DISPATCHER(true)

    // external calls to IDelegationTerms
    onDelegationWithdrawn(address,address[],uint256[]) => CONSTANT
    onDelegationReceived(address,address[],uint256[]) => CONSTANT
    
    // external calls to PauserRegistry
    pauser() returns (address) => DISPATCHER(true)
	unpauser() returns (address) => DISPATCHER(true)

    // external calls to ERC20
    balanceOf(address) returns (uint256) => DISPATCHER(true)
    transfer(address, uint256) returns (bool) => DISPATCHER(true)
    transferFrom(address, address, uint256) returns (bool) => DISPATCHER(true)

    // external calls to ERC1271 (can import OpenZeppelin mock implementation)
    // isValidSignature(bytes32 hash, bytes memory signature) returns (bytes4 magicValue) => DISPATCHER(true)
    isValidSignature(bytes32, bytes) returns (bytes4) => DISPATCHER(true)

    //// Harnessed Functions
    // Harnessed calls
    // Harnessed getters
    strategy_is_in_stakers_array(address, address) returns (bool) envfree
    num_times_strategy_is_in_stakers_array(address, address) returns (uint256) envfree
    totalShares(address) returns (uint256) envfree

	//// Normal Functions
	stakerStrategyListLength(address) returns (uint256) envfree
    stakerStrategyList(address, uint256) returns (address) envfree
    stakerStrategyShares(address, address) returns (uint256) envfree
    array_exhibits_properties(address) returns (bool) envfree
}

invariant stakerStrategyListLengthLessThanOrEqualToMax(address staker)
	stakerStrategyListLength(staker) <= 32

// verifies that strategies in the staker's array of strategies are not duplicated, and that the staker has nonzero shares in each one
invariant arrayExhibitsProperties(address staker)
    array_exhibits_properties(staker) == true
        {
            preserved
            {
                requireInvariant stakerStrategyListLengthLessThanOrEqualToMax(staker);
            }
        }

// if a strategy is *not* in staker's array of strategies, then the staker should have precisely zero shares in that strategy
invariant strategiesNotInArrayHaveZeroShares(address staker, uint256 index)
    (index >= stakerStrategyListLength(staker)) => (stakerStrategyShares(staker, stakerStrategyList(staker, index)) == 0)

/**
* a staker's amount of shares in a strategy (i.e. `stakerStrategyShares[staker][strategy]`) should only increase when
* `depositIntoStrategy`, `depositIntoStrategyWithSignature`, or `depositBeaconChainETH` has been called
* *OR* when completing a withdrawal
*/
definition methodCanIncreaseShares(method f) returns bool =
    f.selector == depositIntoStrategy(address,address,uint256).selector
    || f.selector == depositIntoStrategyWithSignature(address,address,uint256,address,uint256,bytes).selector
    || f.selector == depositBeaconChainETH(address,uint256).selector
    || f.selector == completeQueuedWithdrawal((address[],uint256[],address,(address,uint96),uint32,address),address[],uint256,bool).selector;
    // || f.selector == slashQueuedWithdrawal(address,bytes,address[],uint256[]).selector
    // || f.selector == slashShares(address,address,address[],address[],uint256[],uint256[]).selector;

/**
* a staker's amount of shares in a strategy (i.e. `stakerStrategyShares[staker][strategy]`) should only decrease when
* `queueWithdrawal`, `slashShares`, or `recordOvercommittedBeaconChainETH` has been called
*/
definition methodCanDecreaseShares(method f) returns bool =
    f.selector == queueWithdrawal(uint256[],address[],uint256[],address,bool).selector
    || f.selector == slashShares(address,address,address[],address[],uint256[],uint256[]).selector
    || f.selector == recordOvercommittedBeaconChainETH(address,uint256,uint256).selector;

rule sharesAmountsChangeOnlyWhenAppropriateFunctionsCalled(address staker, address strategy) {
    uint256 sharesBefore = stakerStrategyShares(staker, strategy);
    method f;
    env e;
    calldataarg args;
    f(e,args);
    uint256 sharesAfter = stakerStrategyShares(staker, strategy);
    assert(sharesAfter > sharesBefore => methodCanIncreaseShares(f));
    assert(sharesAfter < sharesBefore => methodCanDecreaseShares(f));
}

// based on Certora's example here https://github.com/Certora/Tutorials/blob/michael/ethcc/EthCC/Ghosts/ghostTest.spec
ghost mapping(address => mathint) sumOfSharesInStrategy {
  init_state axiom forall address strategy. sumOfSharesInStrategy[strategy] == 0;
}

hook Sstore stakerStrategyShares[KEY address staker][KEY address strategy] uint256 newValue (uint256 oldValue) STORAGE {
    sumOfSharesInStrategy[strategy] = sumOfSharesInStrategy[strategy] + newValue - oldValue;
}

/**
* Verifies that the `totalShares` returned by an Strategy is always greater than or equal to the sum of shares in the `stakerStrategyShares`
* mapping -- specifically, that `strategy.totalShares() >= sum_over_all_stakers(stakerStrategyShares[staker][strategy])`
* We cannot show strict equality here, since the withdrawal process first decreases a staker's shares (when `queueWithdrawal` is called) and
* only later is `totalShares` decremented (when `completeQueuedWithdrawal` is called).
*/
invariant totalSharesGeqSumOfShares(address strategy)
    totalShares(strategy) >= sumOfSharesInStrategy[strategy]
    // preserved block since does not apply for 'beaconChainETH'
    { preserved {
        // 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0 converted to decimal (this is the address of the virtual 'beaconChainETH' strategy)
        // require strategy != beaconChainETHStrategy();
        require strategy != 1088545275507480024404324736574744392984337050304;
    } }