// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IInvestmentManager.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IServiceFactory.sol";

abstract contract InvestmentManagerStorage is IInvestmentManager {
    struct WithdrawalStorage {
        uint32 initTimestamp;
        uint32 latestFraudproofTimestamp;
        address withdrawer;
    }
    struct WithdrawerAndNonce {
        address withdrawer;
        uint96 nonce;
    }

    IERC1155 public immutable EIGEN;
    IEigenLayrDelegation public immutable delegation;
    IServiceFactory public immutable serviceFactory;

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
    // staker => cumulative number of queued withdrawals they have ever initiated. only increments (doesn't decrement)
    mapping(address => uint96) public numWithdrawalsQueued;

    constructor(IERC1155 _EIGEN, IEigenLayrDelegation _delegation, IServiceFactory _serviceFactory) {
        EIGEN = _EIGEN;
        delegation = _delegation;
        serviceFactory = _serviceFactory;
    }
}
