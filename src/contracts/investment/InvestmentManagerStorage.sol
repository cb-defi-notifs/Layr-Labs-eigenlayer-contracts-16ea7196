// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IInvestmentManager.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/ISlasher.sol";

abstract contract InvestmentManagerStorage is IInvestmentManager {
    struct WithdrawalStorage {
        uint32 initTimestamp;
        uint32 unlockTimestamp;
        address withdrawer;
    }
    struct WithdrawerAndNonce {
        address withdrawer;
        uint96 nonce;
    }

    // fixed waiting period for withdrawals
    // TODO: set this to a proper interval for production
    uint32 public constant WITHDRAWAL_WAITING_PERIOD = 10 seconds;

    // maximum length of dynamic arrays in `investorStrats` mapping
    uint8 internal constant MAX_INVESTOR_STRATS_LENGTH = 32;

    IEigenLayrDelegation public immutable delegation;
    ISlasher public slasher;

    IInvestmentStrategy public proofOfStakingEthStrat;
    IInvestmentStrategy public consensusLayerEthStrat;

    uint256 public totalEigenStaked;
    address public eigenLayrDepositContract;
    // staker => InvestmentStrategy => num shares
    mapping(address => mapping(IInvestmentStrategy => uint256))
        public investorStratShares;
    // staker => array of strategies in which they have nonzero shares
    mapping(address => IInvestmentStrategy[]) public investorStrats;
    // staker => hash of withdrawal inputs => timestamps & address related to the withdrawal
    mapping(address => mapping(bytes32 => WithdrawalStorage)) public queuedWithdrawals;
    // staker => cumulative number of queued withdrawals they have ever initiated. only increments (doesn't decrement)
    mapping(address => uint96) public numWithdrawalsQueued;

    constructor(IEigenLayrDelegation _delegation) {
        delegation = _delegation;
    }
}
