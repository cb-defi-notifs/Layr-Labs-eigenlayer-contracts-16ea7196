methods {
	stakeHouseMemberQueue(bytes) returns uint256 envfree
	getDepositContractBalance() returns uint256 envfree
}

/// description: Helper function to invoke a function in a parametric way
function invokeParametricByKnotId(env e, method f, bytes knotId) {
    address stakehouse;
    uint256 amount;
    bool slashed;
    address user;
    uint256 savETHIndex;

    uint248 deadline;
    uint8 v;

    bytes32[] rs;
    require rs.length == 2;

    uint64[] reportArr;

    require reportArr.length == 6;

    require v == 28 || v == 27;

	if (f.selector == topUpSlashedSlot(address,bytes,address,uint256).selector) {
	    topUpSlashedSlot(e, stakehouse, knotId, user, amount);
	}

	else if (f.selector == balanceIncrease(address,bytes,(bytes,bytes,bool,uint64,uint64,uint64,uint64,uint64,uint64),(uint248,uint8,bytes32,bytes32)).selector) {
	    flatten_balanceIncrease(e, stakehouse, knotId, slashed, reportArr, deadline, v, rs);
	}

	else if (f.selector == rageQuitPostDeposit(address,bytes,address,(bytes,bytes,bool,uint64,uint64,uint64,uint64,uint64,uint64),(uint248,uint8,bytes32,bytes32)).selector) {
	    flatten_rageQuitPostDeposit(e, user, knotId, stakehouse, slashed, reportArr, deadline, v, rs);
	}

    else if (f.selector == createStakehouse(address,bytes,string,uint256,(bytes,bytes,bool,uint64,uint64,uint64,uint64,uint64,uint64),(uint248,uint8,bytes32,bytes32)).selector) {
        flatten_createStakehouse(e, user, knotId, savETHIndex, slashed, reportArr, deadline, v, rs);
    }

    else if (f.selector == joinStakeHouseAndCreateBrand(address,bytes,string,address,uint256,(bytes,bytes,bool,uint64,uint64,uint64,uint64,uint64,uint64),(uint248,uint8,bytes32,bytes32)).selector) {
        flatten_joinStakeHouseAndCreateBrand(e, user, knotId, stakehouse, savETHIndex, reportArr, deadline, v, rs);
    }

    else if (f.selector == joinStakehouse(address,bytes,address,uint256,uint256,(bytes,bytes,bool,uint64,uint64,uint64,uint64,uint64,uint64),(uint248,uint8,bytes32,bytes32)).selector) {
        flatten_joinStakehouse(e, user, knotId, stakehouse, slashed, reportArr, deadline, v, rs);
    }

	else {
		calldataarg arg;
		f(e, arg);
	}
}

/// description: Check if representative authorization works
rule representativeAuthorized(env e, address a) {
    authorizeRepresentative(e, a, true);

    bool representativeBefore = userToRepresentativeStatus(e, e.msg.sender, a);
    assert (representativeBefore, "Representative not added");

    authorizeRepresentative(e, a, false);

    bool representativeAfter = userToRepresentativeStatus(e, e.msg.sender, a);
    assert (!representativeAfter, "Representative not removed");
}

/// description: Non-representatives can't register initials for some other actor
rule noInitialRegistrationByNonRepresentative(env e, address user, bytes blsPublicKey, bytes blsSignature) {
  require e.msg.sender != user;

  registerValidatorInitials(e, user, blsPublicKey, blsSignature);
  bool representativeAfter = userToRepresentativeStatus(e, user, e.msg.sender);

  assert (representativeAfter, "Non-representative function call");
}

/// description: Making sure that once ether is sent to the deposit contract from the topUpQueue it's completely cleared
rule topUpQueueClearanceCompletesCorrectly(env e, bytes knotId) {
    require knotId.length == 64;

    uint256 currentQueueBalance = stakeHouseMemberQueue(knotId);

    require currentQueueBalance > 0;

    uint256 sentValue = e.msg.value;
    uint256 expectedBalance = currentQueueBalance + sentValue;

    require expectedBalance >= 1000000000000000000;

    uint256 depositContractBalanceBefore = getDepositContractBalance();

    topUpKNOT(e, knotId);

    uint256 depositContractBalanceAfter = getDepositContractBalance();
    uint256 queueBalanceAfter = stakeHouseMemberQueue(knotId);

    uint256 depositContractBalanceDifference = depositContractBalanceAfter - depositContractBalanceBefore;

    assert depositContractBalanceDifference == expectedBalance => queueBalanceAfter == 0;
}

