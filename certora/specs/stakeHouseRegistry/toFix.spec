// description: Ensure redemption rate only increases with slashing of SLOT
rule redemptionRateGoesUpWithSlashing(env e, bytes blsPubKey, uint256 slashAmount) {
    require blsPubKey.length == 32;

    uint256 redemptionRateBefore = slotReg.redemptionRate(currentContract);

    slotReg.slash(e, currentContract, blsPubKey, slashAmount, false);

    assert slotReg.redemptionRate(currentContract) >= redemptionRateBefore;
}

// description: Ensure redemption rate only increases with slashing of SLOT
rule redemptionRateGoesDownAfterTopUp(env e, bytes blsPubKey, uint256 topUpAmount, address user) {
    require blsPubKey.length == 32;

    uint256 redemptionRateBefore = slotReg.redemptionRate(currentContract);

    slotReg.buySlashedSlot(e, currentContract, blsPubKey, topUpAmount, user);

    assert slotReg.redemptionRate(currentContract) <= redemptionRateBefore;
}