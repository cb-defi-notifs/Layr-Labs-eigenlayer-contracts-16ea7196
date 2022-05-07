// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;


interface IDataLayrPaymentChallenge{
    function challengePaymentHalf(
        bool half,
        uint120 amount1,
        uint120 amount2
    ) external;
}