methods {
    stakeHouseCurrentSLOTSlashed(address) returns (uint256) envfree
    circulatingCollateralisedSlot(address) returns (uint256) envfree
    totalUserCollateralisedSLOTBalanceInHouse(address, address) returns (uint256) envfree  // stakehouse, user

    mint(address,uint256) => DISPATCHER(true)
    burn(address,uint256) => DISPATCHER(true)
    kick(bytes) => DISPATCHER(true)
}

// description: The sum of vault balances across different knots does not exceed total collateralised SLOT user owns across the whole house
ghost sumAllSLOTInVaults() returns mathint {
    init_state axiom sumAllSLOTInVaults() == 0;
}

// description: The sum of vault balances across different knots does not exceed total collateralised SLOT user owns across the whole house
ghost sumOfSlotsPerHouse(address, address) returns mathint {
   init_state axiom forall address a. forall address b. sumOfSlotsPerHouse(a, b) == 0;
}

hook Sstore totalUserCollateralisedSLOTBalanceForKnot[KEY address stakehouse][KEY address user][KEY bytes blsPubKey] uint256 balance
(uint256 old_balance) STORAGE {

  //havoc sumAllSLOTInVaults assuming sumAllSLOTInVaults@new() == sumAllSLOTInVaults@old() +
    //    balance - old_balance;

  havoc sumOfSlotsPerHouse assuming forall address a. forall address b. (a == stakehouse && b == user => sumOfSlotsPerHouse@new(a, b) == sumOfSlotsPerHouse@old(a, b) + balance - old_balance)
  && (a != stakehouse || b != user => sumOfSlotsPerHouse@new(a, b) == sumOfSlotsPerHouse@old(a, b) );
}

<<<<<<< Updated upstream
// description: The sum of vault balances across different knots does not exceed total collateralised SLOT user owns across the whole house
invariant sumAllSLOTInVaultsDoesNotExceedTotalCollateralisedInHouse(address house, address user)
=======
invariant invariant_sumAllSLOTInVaultsDoesNotExceedTotalCollateralisedInHouse(address house, address user)
>>>>>>> Stashed changes
    sumOfSlotsPerHouse(house, user) == totalUserCollateralisedSLOTBalanceInHouse(house, user)
    filtered {
        f -> f.selector != upgradeToAndCall(address,bytes).selector &&
             f.selector != upgradeTo(address).selector
    }
    {
        preserved mintSLOTAndSharesBatch(address a, bytes b, address c) with (env e) {
            require b.length == 32;
        }

        preserved slashAndBuySlot(address a, bytes b, address c, uint256 d, uint256 e, bool f) with (env _e) {
            require b.length == 32;
        }

        preserved slash(address a, bytes b, uint256 c, bool d) with (env e) {
            require b.length == 32;
        }

        preserved buySlashedSlot(address a, bytes b, uint256 c, address d) with (env e) {
            require b.length == 32;
        }

        preserved rageQuitKnotOnBehalfOf(address a, bytes b, address c, address[] d, address e, address f, uint256 g) with (env _e) {
            require b.length == 32;
        }

        preserved markUserKnotAsWithdrawn(address a, bytes b) with (env e) {
            require b.length == 32;
        }
    }

// todo - sum of all user vault balances for a knot does not ever exceed 4 SLOT