
methods {
    indexOwnedByTheVault() returns uint256 envfree
    getBalance(address) returns uint256 envfree

    execute(address, bytes, uint256) returns bytes => DISPATCHER(true)
}

rule shouldWithdrawETHForStaking(env e, address smartWallet, uint256 amount) {
    uint256 smartWalletBalanceBefore = getBalance(smartWallet);
    withdrawETHForStaking(e, smartWallet, amount);
    uint256 smartWalletBalanceAfter = getBalance(smartWallet);

    assert smartWalletBalanceAfter - smartWalletBalanceBefore == amount, "Incorrect wallet transfer amount";
}
