// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IInvestmentManager.sol";
import "./VoteWeigherBaseStorage.sol";

// import "ds-test/test.sol";


/**
 @notice This contract is used for  
 */



contract VoteWeigherBase is 
    IVoteWeigher,
    VoteWeigherBaseStorage 
    // , DSTest
{
    // number of quorums that are being used by the middleware
    uint8 public override immutable NUMBER_OF_QUORUMS;

    constructor(
        IRepository _repository,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager,
        uint8 _NUMBER_OF_QUORUMS
    ) VoteWeigherBaseStorage(_repository, _delegation, _investmentManager) {
        NUMBER_OF_QUORUMS = _NUMBER_OF_QUORUMS;
    }

    /**
     @notice This function computes the total weight of the @param operator in the quorum 
             @param quorumNumber.
     */
    function weightOfOperator(address operator, uint256 quorumNumber) public virtual returns (uint96) {
        uint96 weight;

        if (quorumNumber < NUMBER_OF_QUORUMS) {
            
            uint256 stratsLength = strategiesConsideredAndMultipliersLength(quorumNumber);
            
            StrategyAndWeightingMultiplier memory strategyAndMultiplier;

            if (delegation.isSelfOperator(operator)) {
                for (uint256 i = 0; i < stratsLength;) {

                    // accessing i^th StrategyAndWeightingMultiplier struct for the quorumNumber
                    strategyAndMultiplier = strategiesConsideredAndMultipliers[quorumNumber][i];

                    // shares of the self-operator in the investment strategy
                    uint256 sharesAmount = investmentManager.investorStratShares(operator, strategyAndMultiplier.strategy);
                    
                    // add the weightage from the shares to the total weight
                    if (sharesAmount > 0) {
                        weight += uint96(((strategyAndMultiplier.strategy).sharesToUnderlying(sharesAmount) * strategyAndMultiplier.multiplier) / WEIGHTING_DIVISOR);                   
                    }

                    unchecked {
                        ++i;
                    }
                }
            } else {
                for (uint256 i = 0; i < stratsLength;) {
                    
                    // accessing i^th StrategyAndWeightingMultiplier struct for the quorumNumber
                    strategyAndMultiplier = strategiesConsideredAndMultipliers[quorumNumber][i];

                    // shares of the operator in the investment strategy
                    uint256 sharesAmount = delegation.getOperatorShares(operator, strategyAndMultiplier.strategy);
                    
                    // add the weightage from the shares to the total weight
                    if (sharesAmount > 0) {
                        weight += uint96(((strategyAndMultiplier.strategy).sharesToUnderlying(sharesAmount) * strategyAndMultiplier.multiplier) / WEIGHTING_DIVISOR);                    
                    }

                    unchecked {
                        ++i;
                    }
                }
            }
        }

        return weight;
    }

    /**
     * @notice returns the total Eigen delegated by delegators with this operator
     */
    /**
     * @dev minimum delegation limit has to be satisfied.
     */
    function weightOfOperatorEigen(address operator)
        public virtual
        returns (uint96)
    {
        return weightOfOperator(operator, 1);
    }

    /**
     * @notice returns the total ETH delegated by delegators with this operator.
     */
    /**
      @dev Accounts for both ETH used for staking in Ethereum and the ETH-denominated value 
           of the shares in the investment strategies.
     */
    function weightOfOperatorEth(address operator) public virtual returns (uint96) {
        return weightOfOperator(operator, 0);
    }


    function strategiesConsideredAndMultipliersLength(uint256 quorumNumber) public view returns (uint256) {
        return strategiesConsideredAndMultipliers[quorumNumber].length;
    }


    /**
     @notice Add new strategies and the associated multiplier for the @param quorumNumber  
     */
    function addStrategiesConsideredAndMultipliers(
        uint256 quorumNumber, 
        StrategyAndWeightingMultiplier[] calldata _newStrategiesConsideredAndMultipliers
    ) external onlyRepositoryGovernance {

        uint256 numStrats = _newStrategiesConsideredAndMultipliers.length;

        for (uint256 i = 0; i < numStrats;) {
            strategiesConsideredAndMultipliers[quorumNumber].push(_newStrategiesConsideredAndMultipliers[i]);
            unchecked {
                ++i;
            }
        }
    }


    /**
     @notice This function is used for removing strategies and their associated weight from 
             mapping strategiesConsideredAndMultipliers for a specific @param quorumNumber. 
     */
    /**  
     @dev higher indices should be *first* in the list of @param indicesToRemove
     */
    function removeStrategiesConsideredAndWeights(uint256 quorumNumber, IInvestmentStrategy[] calldata _strategiesToRemove, uint256[] calldata indicesToRemove) external onlyRepositoryGovernance {
        uint256 numStrats = indicesToRemove.length;

        for (uint256 i = 0; i < numStrats;) {
            require(strategiesConsideredAndMultipliers[quorumNumber][indicesToRemove[i]].strategy == _strategiesToRemove[i], "index incorrect");
            
            // removing strategies and their associated weight
            strategiesConsideredAndMultipliers[quorumNumber][indicesToRemove[i]] = strategiesConsideredAndMultipliers[quorumNumber][strategiesConsideredAndMultipliers[quorumNumber].length - 1];
            strategiesConsideredAndMultipliers[quorumNumber].pop();
            
            unchecked {
                ++i;
            }
        }
    }
}