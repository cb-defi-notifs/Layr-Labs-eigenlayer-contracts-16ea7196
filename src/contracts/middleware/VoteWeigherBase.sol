// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IQueryManager.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IInvestmentManager.sol";

contract VoteWeigherBase is IVoteWeigher {
    // TODO: decide if this should be immutable or upgradeable
    IEigenLayrDelegation public delegation;
    // not set in constructor, since the queryManager sets the address of the vote weigher in
    // its own constructor, and therefore the vote weigher must be deployed first
    IQueryManager public queryManager;
    // divisor. X consensus layer ETH is treated as equivalent to (X / consensusLayerEthToEth) ETH locked into EigenLayr
    uint256 public consensusLayerEthToEth;

    constructor(
        IEigenLayrDelegation _delegation,
        uint256 _consensusLayerEthToEth
    ) {
        delegation = _delegation;
        consensusLayerEthToEth = _consensusLayerEthToEth;
    }

    // one-time function for initializing the queryManager
    function setQueryManager(IQueryManager _queryManager) public {
        require(
            address(queryManager) == address(0),
            "Query Manager already set"
        );
        queryManager = _queryManager;
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
    function weightOfOperatorEth(address operator) public virtual returns (uint128) {
        uint128 amount = uint128(
            delegation.getConsensusLayerEthDelegated(operator) /
                consensusLayerEthToEth +
                delegation.getUnderlyingEthDelegated(operator)
        );

        // check that minimum delegation limit is satisfied
        return amount;
    }
}