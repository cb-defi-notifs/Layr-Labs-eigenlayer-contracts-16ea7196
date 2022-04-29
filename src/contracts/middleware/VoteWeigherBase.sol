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

    /**
     * @notice returns the total Eigen delegated by delegators with this operator
     */
    /**
     * @dev minimum delegation limit has to be satisfied.
     */
    function weightOfOperatorEigen(address operator)
        public virtual
        view
        returns (uint128)
    {
        uint128 eigenAmount = uint128(delegation.getEigenDelegated(operator));

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
     //TODO: UPDATE THIS FOR RESPECTED STRATEGIES
    function weightOfOperatorEth(address operator) public virtual returns (uint128) {
        uint256 stratsLength = strategiesConsideredLength();
        uint128 amount;
        if (delegation.isDelegatedToSelf(operator)) {
            for (uint256 i = 0; i < stratsLength;) {
                amount += uint128(investmentManager.investorStratShares(operator, strategiesConsidered[i]));
                unchecked {
                    ++i;
                }
            }
        } else {
            for (uint256 i = 0; i < stratsLength;) {
                amount += uint128(delegation.getOperatorShares(operator, strategiesConsidered[i]));
                unchecked {
                    ++i;
                }
            }
        }
        // uint128 amount = uint128(
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
}