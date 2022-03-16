// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IInvestmentManager.sol";

abstract contract InvestmentManagerStorage is IInvestmentManager {
    mapping(IInvestmentStrategy => bool) public stratEverApproved;
    mapping(IInvestmentStrategy => bool) public stratApproved;
    // staker => InvestmentStrategy => num shares
    mapping(address => mapping(IInvestmentStrategy => uint256))
        public investorStratShares;
    mapping(address => IInvestmentStrategy[]) public investorStrats;
    mapping(address => uint256) public consensusLayerEth;
    mapping(address => uint256) public eigenDeposited;
    uint256 public totalConsensusLayerEthStaked;
    uint256 public totalEigenStaked;
    address public entryExit;
    address public slasher;
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; //placeholder address for native asset
}
