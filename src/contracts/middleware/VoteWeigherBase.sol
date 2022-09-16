// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IInvestmentManager.sol";
import "./VoteWeigherBaseStorage.sol";

// import "forge-std/Test.sol";

/**
 * @notice This contract is used for
 * - computing the total weight of an operator for any of the quorums that are considered
 * by the middleware
 * - addition and removal of strategies and the associated weighting criteria that are assigned
 * by the middleware for each of the quorum(s)
 */
contract VoteWeigherBase is VoteWeigherBaseStorage {

    event StrategyAddedToQuorum(uint256 indexed quorumNumber, IInvestmentStrategy strategy);
    event StrategyRemovedFromQuorum(uint256 indexed quorumNumber, IInvestmentStrategy strategy);

    constructor(
        IRepository _repository,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager,
        uint8 _NUMBER_OF_QUORUMS,
        uint256[] memory _quorumBips
    )
        VoteWeigherBaseStorage(_repository, _delegation, _investmentManager, _NUMBER_OF_QUORUMS, _quorumBips)
    {}

    /**
     * @notice This function computes the total weight of the @param operator in the quorum
     * @param quorumNumber.
     */
    function weightOfOperator(address operator, uint256 quorumNumber) public virtual returns (uint96) {
        uint96 weight;

        if (quorumNumber < NUMBER_OF_QUORUMS) {
            uint256 stratsLength = strategiesConsideredAndMultipliersLength(quorumNumber);

            StrategyAndWeightingMultiplier memory strategyAndMultiplier;

            for (uint256 i = 0; i < stratsLength;) {
                // accessing i^th StrategyAndWeightingMultiplier struct for the quorumNumber
                strategyAndMultiplier = strategiesConsideredAndMultipliers[quorumNumber][i];

                // shares of the operator in the investment strategy
                uint256 sharesAmount = delegation.operatorShares(operator, strategyAndMultiplier.strategy);

                // add the weightage from the shares to the total weight
                if (sharesAmount > 0) {
                    weight += uint96(
                        (
                            (strategyAndMultiplier.strategy).sharesToUnderlying(sharesAmount)
                                * strategyAndMultiplier.multiplier
                        ) / WEIGHTING_DIVISOR
                    );
                }

                unchecked {
                    ++i;
                }
            }
        }

        return weight;
    }

    /**
     * @notice Add new strategies and the associated multiplier to the @param quorumNumber
     */
    function addStrategiesConsideredAndMultipliers(
        uint256 quorumNumber,
        StrategyAndWeightingMultiplier[] memory _newStrategiesConsideredAndMultipliers
    )
        external
        onlyRepositoryGovernance
    {
        _addStrategiesConsideredAndMultipliers(quorumNumber, _newStrategiesConsideredAndMultipliers);
    }

    /**
     * @notice This function is used for removing strategies and their associated weight from
     * mapping strategiesConsideredAndMultipliers for a specific @param quorumNumber.
     */
    /**
     * @dev higher indices should be *first* in the list of @param indicesToRemove, since otherwise
     * the removal of lower index entries will cause a shift in the indices of the other strategiesToRemove
     */
    function removeStrategiesConsideredAndMultipliers(
        uint256 quorumNumber,
        IInvestmentStrategy[] calldata _strategiesToRemove,
        uint256[] calldata indicesToRemove
    )
        external
        onlyRepositoryGovernance
    {
        uint256 numStrats = indicesToRemove.length;

        for (uint256 i = 0; i < numStrats;) {
            require(
                strategiesConsideredAndMultipliers[quorumNumber][indicesToRemove[i]].strategy == _strategiesToRemove[i],
                "VoteWeigherBase.removeStrategiesConsideredAndWeights: index incorrect"
            );

            // removing strategies and their associated weight
            strategiesConsideredAndMultipliers[quorumNumber][indicesToRemove[i]] = strategiesConsideredAndMultipliers[quorumNumber][strategiesConsideredAndMultipliers[quorumNumber]
                .length - 1];
            strategiesConsideredAndMultipliers[quorumNumber].pop();
            emit StrategyRemovedFromQuorum(quorumNumber, _strategiesToRemove[i]);

            unchecked {
                ++i;
            }
        }
    }

    // returns the length of the dynamic array stored in strategiesConsideredAndMultipliers[quorumNumber]
    function strategiesConsideredAndMultipliersLength(uint256 quorumNumber) public view returns (uint256) {
        require(
            quorumNumber < NUMBER_OF_QUORUMS,
            "VoteWeigherBase.strategiesConsideredAndMultipliersLength: quorumNumber input exceeds NUMBER_OF_QUORUMS"
        );
        return strategiesConsideredAndMultipliers[quorumNumber].length;
    }

    function _addStrategiesConsideredAndMultipliers(
        uint256 quorumNumber,
        StrategyAndWeightingMultiplier[] memory _newStrategiesConsideredAndMultipliers
    )
        internal
    {
        uint256 numStratsToAdd = _newStrategiesConsideredAndMultipliers.length;
        uint256 numStratsExisting = strategiesConsideredAndMultipliers[quorumNumber].length;
        require(
            numStratsExisting + numStratsToAdd <= MAX_WEIGHING_FUNCTION_LENGTH,
            "VoteWeigherBase._addStrategiesConsideredAndMultipliers: exceed MAX_WEIGHING_FUNCTION_LENGTH"
        );
        for (uint256 i = 0; i < numStratsToAdd;) {
            // fairly gas-expensive internal loop to make sure that the *same* strategy cannot be added multiple times
            for (uint256 j = 0; j < (numStratsExisting + i);) {
                require(
                    strategiesConsideredAndMultipliers[quorumNumber][j].strategy
                        != _newStrategiesConsideredAndMultipliers[i].strategy,
                    "VoteWeigherBase._addStrategiesConsideredAndMultipliers: cannot add same strategy 2x"
                );
                unchecked {
                    ++j;
                }
            }
            strategiesConsideredAndMultipliers[quorumNumber].push(_newStrategiesConsideredAndMultipliers[i]);
            emit StrategyAddedToQuorum(quorumNumber, _newStrategiesConsideredAndMultipliers[i].strategy);
            unchecked {
                ++i;
            }
        }
    }
}
