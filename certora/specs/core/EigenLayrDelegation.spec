import "../../ComplexityCheck/erc20.spec"

methods {
    //// External Calls
	// external calls to EigenLayrDelegation 
    undelegate(address) => DISPATCHER(true)
    isDelegated(address) returns (bool) => DISPATCHER(true)
    delegatedTo(address) returns (address) => DISPATCHER(true)
    decreaseDelegatedShares(address,address[],uint256[]) => DISPATCHER(true)
	increaseDelegatedShares(address,address,uint256) => DISPATCHER(true)

	// external calls to Slasher
    isFrozen(address) returns (bool) => DISPATCHER(true)
	canWithdraw(address,uint32,uint256) returns (bool) => DISPATCHER(true)

	// external calls to InvestmentManager
    getDeposits(address) returns (address[],uint256[]) => DISPATCHER(true)
    slasher() returns (address) => DISPATCHER(true)
	deposit(address,uint256) returns (uint256) => DISPATCHER(true)
	withdraw(address,address,uint256) => DISPATCHER(true)

	// external calls to EigenPodManager
	withdrawBeaconChainETH(address,address,uint256) => DISPATCHER(true)
	
    // external calls to EigenPod
	withdrawBeaconChainETH(address,uint256) => DISPATCHER(true)
    
    // external calls to PauserRegistry
    pauser() returns (address) => DISPATCHER(true)
	unpauser() returns (address) => DISPATCHER(true)
	
    //// Harnessed Functions
    // Harnessed calls
    decreaseDelegatedShares(address,address,address,uint256,uint256)
    // Harmessed getters
    get_operatorShares(address,address) returns(uint256) envfree

    //// Summarized Functions
    _delegationReceivedHook(address,address,address[],uint256[]) => NONDET
    _delegationWithdrawnHook(address,address,address[],uint256[]) => NONDET

    //envfree functions
    isDelegated(address staker) returns (bool) envfree
    isNotDelegated(address staker) returns (bool) envfree
    isOperator(address operator) returns (bool) envfree
    delegatedTo(address staker) returns (address) envfree
    delegationTerms(address operator) returns (address) envfree
    operatorShares(address operator, address strategy) returns (uint256) envfree
}

/*
LEGAL STATE TRANSITIONS:
1)
FROM not delegated -- defined as delegatedTo(staker) == address(0), likewise returned by isNotDelegated(staker)--
AND not registered as an operator -- defined as isOperator(operator) == false, or equivalently, delegationTerms(operator) == 0,
TO delegated but not an operator
in this case, the end state is that:
isOperator(staker) == false,
delegatedTo(staker) != staker && delegatedTo(staker) != 0,
and isDelegated(staker) == true (redundant with above)
-only allowed when calling `delegateTo` or `delegateToBySignature`

2)
FROM not delegated AND not registered as an operator
TO an operator
in this case, the end state is that:
isOperator(staker) == true,
delegatedTo(staker) == staker,
and isDelegated(staker) == true (redundant with above)
-only allowed when calling `registerAsOperator`

3)
FROM not registered as an operator AND delegated
TO not delegated (and still not registered as an operator)
in this case, the end state is that:
isOperator(staker) == false,
delegatedTo(staker) == 0,
and isDelegated(staker) == false (redundant with above)

ILLEGAL STATE TRANSITIONS:
A)
FROM registered as an operator
TO not registered as an operator

B) 
FROM registered as an operator (necessarily implies they are also delegated to themselves)
TO not delegated to themselves

FORBIDDEN STATES:
-an address cannot be simultaneously (classified as an operator) and (not delegated to themselves)
*/

invariant operatorsAlwaysDelegatedToSelf(address operator)
    (operator != 0 && isOperator(operator)) => delegatedTo(operator) == operator

/*
rule batchEquivalence {
    env e;
    storage initial = lastStorage;
    address staker;
    address strategy1;
    address strategy2;
    uint256 share1;
    uint256 share2;

    mathint _operatorSharesStrategy1 = get_operatorShares(staker, strategy1);
    mathint _operatorSharesStrategy2 = get_operatorShares(staker, strategy2);

    decreaseDelegatedShares(e,staker,strategy1,strategy2,share1,share2);

    mathint operatorSharesStrategy1_batch = get_operatorShares(staker, strategy1);
    mathint operatorSharesStrategy2_batch = get_operatorShares(staker, strategy2);

    decreaseDelegatedShares(e,staker,strategy1,share1) at initial;
    decreaseDelegatedShares(e,staker,strategy2,share2);

    mathint operatorSharesStrategy1_single = get_operatorShares(staker, strategy1);
    mathint operatorSharesStrategy2_single = get_operatorShares(staker, strategy2);

    assert operatorSharesStrategy1_single == operatorSharesStrategy1_batch 
        && operatorSharesStrategy2_single == operatorSharesStrategy2_batch, 
        "operatorShares must be affected in the same way";
}
*/
/*
invariant zeroAddrHasNoShares(address strategy)
    get_operatorShares(0,strategy) == 0
*/