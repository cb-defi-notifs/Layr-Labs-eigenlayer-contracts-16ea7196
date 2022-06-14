// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IInvestmentManager.sol";
import "./VoteWeigherBaseStorage.sol";

contract VoteWeigherBase is IVoteWeigher, VoteWeigherBaseStorage {

    constructor(
        IRepository _repository,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager,
        uint256 _consensusLayerEthToEth,
        IInvestmentStrategy[] memory _strategiesConsidered
    ) VoteWeigherBaseStorage(_repository, _delegation, _investmentManager) {
        consensusLayerEthToEth = _consensusLayerEthToEth;
        strategiesConsidered = _strategiesConsidered;
    }

    modifier onlyRepositoryGovernance() {
        require(
            address(repository.owner()) == msg.sender,
            "only repository governance can call this function"
        );
        _;
    }

    function weightOfOperator(address operator, uint256 quorumNumber) public virtual returns (uint96) {
        // ETH quorum
        if (quorumNumber == 0) {
            return weightOfOperatorEth(operator);
        // EIGEN quorum
        } else if (quorumNumber == 1) {
            return weightOfOperatorEigen(operator);
        } else {
            return 0;
        }
    }

    /**
     * @notice returns the total Eigen delegated by delegators with this operator
     */
    /**
     * @dev minimum delegation limit has to be satisfied.
     */
    function weightOfOperatorEigen(address operator)
        public virtual
        view
        returns (uint96)
    {
        uint96 eigenAmount = uint96(delegation.getEigenDelegated(operator));

        // check that minimum delegation limit is satisfied
        return eigenAmount;
    }

    /**
     * @notice returns the total ETH delegated by delegators with this operator.
     */
    /**
     * @dev Accounts for both ETH used for staking in settlement layer (via operator)
     *      and the ETH-denominated value of the shares in the investment strategies.
     *      Note that the DataLayr can decide for itself how much weight it wants to
     *      give to the ETH that is being used for staking in settlement layer.
     */
    function weightOfOperatorEth(address operator) public virtual returns (uint96) {
        uint256 stratsLength = strategiesConsideredLength();
        uint96 amount;
        if (delegation.isSelfOperator(operator)) {
            for (uint256 i = 0; i < stratsLength;) {
                uint256 sharesAmount = investmentManager.investorStratShares(operator, strategiesConsidered[i]);
                if (sharesAmount > 0) {
                    amount += uint96(strategiesConsidered[i].sharesToUnderlying(sharesAmount));                    
                }
                unchecked {
                    ++i;
                }
            }
        } else {
            for (uint256 i = 0; i < stratsLength;) {
                uint256 sharesAmount = delegation.getOperatorShares(operator, strategiesConsidered[i]);
                if (sharesAmount > 0) {
                    amount += uint96(strategiesConsidered[i].sharesToUnderlying(sharesAmount));                                        
                }
                unchecked {
                    ++i;
                }
            }
        }
        // uint96 amount = uint96(
        //     delegation.getConsensusLayerEthDelegated(operator) /
        //         consensusLayerEthToEth +
        //         delegation.getUnderlyingEthDelegated(operator)
        // );

        // check that minimum delegation limit is satisfied
        return amount;
    }

    function strategiesConsideredLength() public view returns (uint256) {
        return strategiesConsidered.length;
    }

    function updateStrategiesConsidered(IInvestmentStrategy[] calldata _strategiesConsidered) external onlyRepositoryGovernance {
        strategiesConsidered = _strategiesConsidered;
    }

    function addStrategiesConsidered(IInvestmentStrategy[] calldata _newStrategiesConsidered) external onlyRepositoryGovernance {
        uint256 numStrats = _newStrategiesConsidered.length;
        for (uint256 i = 0; i < numStrats;) {
            strategiesConsidered.push(_newStrategiesConsidered[i]);
            unchecked {
                ++i;
            }
        }
    }

    // NOTE: higher indices should be *first* in the list of indicesToRemove
    function removeStrategiesConsidered(IInvestmentStrategy[] calldata _strategiesToRemove, uint256[] calldata indicesToRemove) external onlyRepositoryGovernance {
        uint256 numStrats = indicesToRemove.length;
        for (uint256 i = 0; i < numStrats;) {
            require(strategiesConsidered[indicesToRemove[i]] == _strategiesToRemove[i], "index incorrect");
            strategiesConsidered[indicesToRemove[i]] = strategiesConsidered[strategiesConsidered.length - 1];
            strategiesConsidered.pop();
            unchecked {
                ++i;
            }
        }
    }
}