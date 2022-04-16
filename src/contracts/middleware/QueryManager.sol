// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../governance/Timelock.sol";
import "../interfaces/IInvestmentStrategy.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IQueryManager.sol";
import "../interfaces/IRegistrationManager.sol";
import "../utils/Initializable.sol";
import "./storage/QueryManagerStorage.sol";
import "./QueryManager_Overhead.sol";

/**
 * @notice This is the contract for managing queries in any middleware. Each middleware has a
 *         a query manager. The main functionalities of this contract are:
 *             - Enable mechanism for an operator to register with the middleware so that it can
 *               respond to the middleware's queries,
 *             - Enable mechanism for an operator to de-register with the middleware,
 *             - Enable mechanism for updating the stake that is being deployed by an
 *               operator for validating the queries of the middleware,
 *             - Enable mechanism for creating new queries by the middleware, responding to
 *               existing queries by operators and finalize the outcome of the queries.
 */
contract QueryManager is QueryManager_Overhead {

    function initialize(
        IVoteWeigher _voteWeigher,
        uint256 _queryDuration,
        uint256 _consensusLayerEthToEth,
        IFeeManager _feeManager,
        IRegistrationManager _registrationManager,
        uint256 _timelockDelay,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager
    ) external initializer {
        _setVoteWeigher(_voteWeigher);
        queryDuration = _queryDuration;
        consensusLayerEthToEth = _consensusLayerEthToEth;
        feeManager = _feeManager;
        registrationManager = _registrationManager;
        Timelock _timelock = new Timelock(address(this), _timelockDelay);
        _setTimelock(_timelock);
        delegation = _delegation;
        investmentManager = _investmentManager;
    }

    /**
     * @notice Used by an operator to de-register itself from providing service to the middleware.
     */
    function deregister(bytes calldata data) external {
        require(
            operatorType[msg.sender] != 0,
            "Registrant is not registered with this middleware."
        );
        require(
            registrationManager.deregisterOperator(msg.sender, data),
            "Deregistration not permitted"
        );

        // subtract the staked Eigen and ETH of the operator, that is getting deregistered,
        // from the total stake securing the middleware
        totalStake.ethStaked -= operatorStakes[msg.sender].ethStaked;
        totalStake.eigenStaked -= operatorStakes[msg.sender].eigenStaked;

        // clear the staked Eigen and ETH of the operator which is getting deregistered
        operatorStakes[msg.sender].ethStaked = 0;
        operatorStakes[msg.sender].eigenStaked = 0;

        // the operator is recorded as being no longer active
        operatorType[msg.sender] = 0;

        //decrement number of registrants
        unchecked {
            --numRegistrants;
        }
        emit Deregistration(msg.sender);
    }

    // call registration contract with given data
    /**
     * @notice Used by an operator to register itself for providing service to the middleware
     *         associated with this QueryManager contract. This also notifies the stakers that
     *         the account has registered itself as an operator.
     */
    /**
     * @param data is an encoding of the operatorType that the operator wants to register as
     *        with the middleware, infrastructure details that the middleware would need for
     *        coordinating with the operator to elicit its response, etc. Details may
     *        vary from middleware to middleware.
     */
    /**
     * @dev Uses the RegistrationManager contract for registering the operator.
     */
    function register(bytes calldata data) external {
        // TODO: eliminate operatorType entirely?
        require(
            operatorType[msg.sender] == 0,
            "Registrant is already registered"
        );

        /**
         * This function calls the registerOperator function of the middleware to process the
         * data that has been provided by the operator, and get their total delegated ETH
         * and EIGEN amounts
         */
        (uint96 ethAmount, uint96 eigenAmount) = registrationManager
            .registerOperator(msg.sender, data);

        // only 1 SSTORE
        operatorStakes[msg.sender] = Stake(uint128(ethAmount), eigenAmount);

        /**
         * update total Eigen and ETH tha are being employed by the operator for securing
         * the queries from middleware via EigenLayr
         */
        //i think this gets batched as 1 SSTORE @TODO check
        totalStake.ethStaked += uint128(ethAmount);
        totalStake.eigenStaked += eigenAmount;

        //TODO: do we need this variable at all?
        //increment number of registrants
        unchecked {
            ++numRegistrants;
        }

        emit Registration(msg.sender);
    }

    /**
     * @notice This function can be called by anyone to update the assets that have been
     *         deposited by the specified operator for validation of middleware.
     */
    /**
     * @return (updated ETH, updated Eigen) staked with the operator
     */
    function updateStake(address operator)
        public
        override
        returns (uint128, uint128)
    {
        // store old stake in memory
        Stake memory prevStake = operatorStakes[operator];

        // get new updated Eigen and ETH that has been delegated by the delegators, and store the updated stake
        Stake memory newStake = 
            Stake({
                ethStaked: voteWeigher.weightOfOperatorEth(operator),
                eigenStaked: voteWeigher.weightOfOperatorEigen(operator)
            });
        operatorStakes[operator] = newStake;

        // update the total stake
        totalStake.ethStaked = totalStake.ethStaked + newStake.ethStaked - prevStake.ethStaked;
        totalStake.eigenStaked = totalStake.eigenStaked + newStake.eigenStaked - prevStake.eigenStaked;

        //return (updated ETH, updated Eigen) staked with the operator
        return (newStake.ethStaked, newStake.eigenStaked);
    }

    /// @notice get total ETH staked for securing the middleware
    function totalEthStaked() public view returns (uint128) {
        return totalStake.ethStaked;
    }

    /// @notice get total Eigen staked for securing the middleware
    function totalEigenStaked() public view returns (uint128) {
        return totalStake.eigenStaked;
    }

    /// @notice get total ETH staked by delegators of the operator
    function ethStakedByOperator(address operator)
        public
        view
        returns (uint128)
    {
        return operatorStakes[operator].ethStaked;
    }

    /// @notice get total Eigen staked by delegators of the operator
    function eigenStakedByOperator(address operator)
        public
        view
        returns (uint128)
    {
        return operatorStakes[operator].eigenStaked;
    }

    /// @notice get both total ETH and Eigen staked by delegators of the operator
    function ethAndEigenStakedForOperator(address operator)
        public
        view
        returns (uint128, uint128)
    {
        Stake memory opStake = operatorStakes[operator];
        return (opStake.ethStaked, opStake.eigenStaked);
    }

    /// @notice sets the fee manager for the middleware's query manager
    function setFeeManager(IFeeManager _feeManager) external onlyTimelock {
        feeManager = _feeManager;
    }

    /// @notice sets the registration manager for the middleware's query manager
    function setRegistrationManager(IRegistrationManager _registrationManager) external onlyTimelock {
        registrationManager = _registrationManager;
    }

    /// @notice sets the vote weigher for the middleware's query manager
    function setVoteWeigher(IVoteWeigher _voteWeigher) external onlyTimelock {
        _setVoteWeigher(_voteWeigher);
    }

    function _setVoteWeigher(IVoteWeigher _voteWeigher) internal {
        voteWeigher = _voteWeigher;
    }
}
