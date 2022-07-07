// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IPaymentManager.sol";

interface IDataLayrPaymentManager is IPaymentManager {
    function challengePaymentHalf(
        bool half,
        uint120 amount1,
        uint120 amount2
    ) external;

    function getChallengeStatus() external returns(uint8);
    
    function getAmount1() external returns (uint120);
    
    function getAmount2() external returns (uint120);
    
    function getToDataStoreId() external returns (uint48);
    
    function getFromDataStoreId() external returns (uint48);
    
    function getDiff() external returns (uint48);
    
    function resolvePaymentChallenge(bool) external;
}
