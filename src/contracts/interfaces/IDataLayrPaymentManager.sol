// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IPaymentManager.sol";

interface IDataLayrPaymentManager is IPaymentManager {
    function challengePaymentHalf(
        address operator,
        bool half,
        uint120 amount1,
        uint120 amount2
    ) external;

    enum PaymentStatus{ 
        COMMITED, 
        REDEEMED
    }

    enum ChallengeStatus{ 
        COMMITED, 
        REDEEMED, 
        OPERATOR_TURN, 
        CHALLENGER_TURN, 
        OPERATOR_TURN_ONE_STEP, 
        CHALLENGER_TURN_ONE_STEP
    }

    function getChallengeStatus(address operator) external view returns(ChallengeStatus);
        
    function getAmount1(address operator) external returns (uint120);
    
    function getAmount2(address operator) external returns (uint120);
    
    function getToDataStoreId(address operator) external returns (uint48);
    
    function getFromDataStoreId(address operator) external returns (uint48);
    
    function getDiff(address operator) external returns (uint48);
}
