// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "../interfaces/IInvestmentManager.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/ISlasher.sol";

abstract contract InvestmentManagerStorage is IInvestmentManager {

    // fixed waiting period for withdrawals
    // TODO: set this to a proper interval for production
    uint32 public constant WITHDRAWAL_WAITING_PERIOD = 10 seconds;

    // maximum length of dynamic arrays in `investorStrats` mapping, for sanity's sake
    uint8 internal constant MAX_INVESTOR_STRATS_LENGTH = 32;

    // system contracts
    IEigenLayrDelegation public immutable delegation;
    ISlasher public slasher;

    // staker => InvestmentStrategy => number of shares which they currently hold
    mapping(address => mapping(IInvestmentStrategy => uint256)) public investorStratShares;
    // staker => array of strategies in which they have nonzero shares
    mapping(address => IInvestmentStrategy[]) public investorStrats;
    // staker => hash of withdrawal inputs => timestamps & address related to the withdrawal
    mapping(address => mapping(bytes32 => WithdrawalStorage)) public queuedWithdrawals;
    // staker => cumulative number of queued withdrawals they have ever initiated. only increments (doesn't decrement)
    mapping(address => uint256) public numWithdrawalsQueued;

    constructor(IEigenLayrDelegation _delegation) {
        delegation = _delegation;
    }
}
