// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IERC20.sol";
import "../../interfaces/MiddlewareInterfaces.sol";
import "../../interfaces/CoreInterfaces.sol";
import "../../interfaces/InvestmentInterfaces.sol";
import "../QueryManager.sol";


contract DataLayrVoteWeigher is IVoteWeighter {
    IInvestmentManager public investmentManager;
    //consensus layer ETH counts for 'consensusLayerPercent'/100 when compared to ETH deposited in the system itself
    uint256 public consensusLayerPercent = 10;
    
    constructor(IInvestmentManager _investmentManager){
        investmentManager = _investmentManager;
    }

    function weightOfOperator(address user) external returns(uint256) {
        uint256 weight = (investmentManager.getConsensusLayerEth(user) * consensusLayerPercent) / 100;
        IInvestmentStrategy[] memory investorStrats = investmentManager.getStrategies(user);
        uint256[] memory investorShares = investmentManager.getStrategyShares(user);
        for (uint256 i = 0; i < investorStrats.length; i++) {
            weight += investorStrats[i].underlyingEthValueOfShares(investorShares[i]);
        }
        return weight;
    }

    function weightOfOperatorView(address user) external view returns(uint256) {
        uint256 weight = (investmentManager.getConsensusLayerEth(user) * consensusLayerPercent) / 100;
        IInvestmentStrategy[] memory investorStrats = investmentManager.getStrategies(user);
        uint256[] memory investorShares = investmentManager.getStrategyShares(user);
        for (uint256 i = 0; i < investorStrats.length; i++) {
            weight += investorStrats[i].underlyingEthValueOfSharesView(investorShares[i]);
        }
        return weight;
    }
    
}