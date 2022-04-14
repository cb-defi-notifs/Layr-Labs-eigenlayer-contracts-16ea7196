// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IInvestmentManager.sol";

abstract contract InvestmentManagerStorage is IInvestmentManager {
    struct WithdrawalStorage {
        uint32 initTimestamp;
        uint32 latestFraudproofTimestamp;
        address withdrawer;
    }
    mapping(IInvestmentStrategy => bool) public stratEverApproved;
    mapping(IInvestmentStrategy => bool) public stratApproved;
    // staker => InvestmentStrategy => num shares
    mapping(address => mapping(IInvestmentStrategy => uint256))
        public investorStratShares;
    mapping(address => IInvestmentStrategy[]) public investorStrats;
    mapping(address => uint256) public consensusLayerEth;
    mapping(address => uint256) public eigenDeposited;
    // staker => hash of withdrawal inputs => timestamps related to the withdrawal
    mapping(address => mapping(bytes32 => WithdrawalStorage)) public queuedWithdrawals;
    uint256 public totalConsensusLayerEthStaked;
    uint256 public totalEigenStaked;
    address public slasher;
    address public eigenLayrDepositContract;
    // placeholder address for native asset
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    // fixed waiting period for withdrawals
    // TODO: set this to a proper interval!
    uint32 internal constant WITHDRAWAL_WAITING_PERIOD = 10 seconds;
    uint256 constant eigenTokenId = 0;
}
