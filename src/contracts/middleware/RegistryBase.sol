// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "../interfaces/IServiceManager.sol";
import "../interfaces/IQuorumRegistry.sol";
import "../libraries/BytesLib.sol";
import "./Repository.sol";
import "./VoteWeigherBase.sol";
import "../libraries/BLS.sol";

// import "forge-std/Test.sol";

/**
 * @notice This contract is used for 
            - registering new operators 
            - committing to and finalizing de-registration as an operator 
            - updating the stakes of the operator
 */

abstract contract RegistryBase is
    IQuorumRegistry,
    VoteWeigherBase
    // ,DSTest
{
    using BytesLib for bytes;

    uint128 public nodeStakeFirstQuorum = 1 wei;
    uint128 public nodeStakeSecondQuorum = 1 wei;
    
    /// @notice a sequential counter that is incremented whenver new operator registers
    uint32 public nextOperatorId;

    /// @notice used for storing Operator info on each operator while registration
    mapping(address => Operator) public registry;

    /// @notice used for storing the list of current and past registered operators 
    address[] public operatorList;

    /// @notice array of the history of the total stakes -- marked as internal since getTotalStakeFromIndex is a getter for this
    OperatorStake[] internal totalStakeHistory;

    /// @notice array of the history of the number of operators, and the taskNumbers at which the number of operators changed
    OperatorIndex[] public totalOperatorsHistory;

    /// @notice mapping from operator's pubkeyhash to the history of their stake updates
    mapping(bytes32 => OperatorStake[]) public pubkeyHashToStakeHistory;

    /// @notice mapping from operator's pubkeyhash to the history of their index in the array of all operators
    mapping(bytes32 => OperatorIndex[]) public pubkeyHashToIndexHistory;

    // EVENTS
    event StakeAdded(
        address operator,
        uint96 firstQuorumStake,
        uint96 secondQuorumStake,
        uint256 updateNumber,
        uint32 updateBlockNumber,
        uint32 prevUpdateBlockNumber
    );

    event StakeUpdate(
        address operator,
        uint96 firstQuorumStake,
        uint96 secondQuorumStake,
        uint32 updateBlockNumber,
        uint32 prevUpdateBlockNumber
    );

    event Deregistration(
        address operator,
        address swapped
    );

    constructor(
        Repository _repository,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager,
        uint8 _NUMBER_OF_QUORUMS,
        uint256[] memory _quorumBips,
        StrategyAndWeightingMultiplier[] memory _firstQuorumStrategiesConsideredAndMultipliers,
        StrategyAndWeightingMultiplier[] memory _secondQuorumStrategiesConsideredAndMultipliers
    )
        VoteWeigherBase(
            _repository,
            _delegation,
            _investmentManager,
            _NUMBER_OF_QUORUMS,
            _quorumBips
        )
    {
        // push an empty OperatorStake struct to the total stake history to record starting with zero stake
        OperatorStake memory _totalStake;
        totalStakeHistory.push(_totalStake);

        // push an empty OperatorIndex struct to the total operators history to record starting with zero operators
        OperatorIndex memory _totalOperators;
        totalOperatorsHistory.push(_totalOperators);

        _addStrategiesConsideredAndMultipliers(0, _firstQuorumStrategiesConsideredAndMultipliers);
        _addStrategiesConsideredAndMultipliers(1, _secondQuorumStrategiesConsideredAndMultipliers);
    }
    
    /*
     looks up the `operator`'s index in the dynamic array `operatorList` at the specified `blockNumber`.
     The `index` input is used to specify the entry within the dynamic array `pubkeyHashToIndexHistory[pubkeyHash]`
     to read data from, where `pubkeyHash` is looked up from `operator`'s registration info
    */
    function getOperatorIndex(address operator, uint32 blockNumber, uint32 index) external view returns (uint32) {
        // look up the operator's stored pubkeyHash
        bytes32 pubkeyHash = getOperatorPubkeyHash(operator);

        require(index < uint32(pubkeyHashToIndexHistory[pubkeyHash].length), "RegistryBase.getOperatorIndex: Operator indexHistory index exceeds array length");
        /*
         // since the 'to' field represents the taskNumber at which a new index started
         // it is OK if the previous array entry has 'to' == blockNumber, so we check not strict inequality here
        */
        require(
            index == 0 || pubkeyHashToIndexHistory[pubkeyHash][index - 1].toBlockNumber <= blockNumber,
            "RegistryBase.getOperatorIndex: Operator indexHistory index is too high"
        );
        OperatorIndex memory operatorIndex = pubkeyHashToIndexHistory[pubkeyHash][index];
        /*
         // when deregistering, the operator does *not* serve the current block number -- 'to' gets set (from zero) to the current block number
         // since the 'to' field represents the blocknumber at which a new index started, we want to check strict inequality here
        */
        require(operatorIndex.toBlockNumber == 0 || blockNumber < operatorIndex.toBlockNumber, "RegistryBase.getOperatorIndex: indexHistory index is too low");
        return operatorIndex.index;
    }

    /*
     looks up the number of total operators at the specified `blockNumber`.
     The `index` input is used to specify the entry within the dynamic array `totalOperatorsHistory` to read data from
    */
    function getTotalOperators(uint32 blockNumber, uint32 index) external view returns (uint32) {
        require(index < uint32(totalOperatorsHistory.length), "RegistryBase.getTotalOperators: TotalOperator indexHistory index exceeds array length");
        // since the 'to' field represents the blockNumber at which a new index started
        // it is OK if the previous array entry has 'to' == blockNumber, so we check not strict inequality here
        require(
            index == 0 || totalOperatorsHistory[index - 1].toBlockNumber <= blockNumber,
            "RegistryBase.getTotalOperators: TotalOperator indexHistory index is too high"
        );
        OperatorIndex memory operatorIndex = totalOperatorsHistory[index];
        // since the 'to' field represents the blockNumber at which a new index started, we want to check strict inequality here
        require(operatorIndex.toBlockNumber == 0 || blockNumber < operatorIndex.toBlockNumber, "RegistryBase.getTotalOperators: indexHistory index is too low");
        return operatorIndex.index;
        
    }

    function setNodeStakeSecondQuorum(uint128 _nodeStakeSecondQuorum)
        external
        onlyRepositoryGovernance
    {
        nodeStakeSecondQuorum = _nodeStakeSecondQuorum;
    }

    function setNodeStakeFirstQuorum(uint128 _nodeStakeFirstQuorum)
        external
        onlyRepositoryGovernance
    {
        nodeStakeFirstQuorum = _nodeStakeFirstQuorum;
    }

    /// @notice returns the unique ID of the specified operator 
    function getOperatorId(address operator) external view returns (uint32) {
        return registry[operator].id;
    }

    /// @notice returns the active status for the specified operator
    function getOperatorStatus(address operator) external view returns(IQuorumRegistry.Active) {
        return registry[operator].active;
    }

    function getOperatorPubkeyHash(address operator) public view returns(bytes32) {
        return registry[operator].pubkeyHash;
    }

    function getStakeFromPubkeyHashAndIndex(bytes32 pubkeyHash, uint256 index)
        external
        view
        returns (OperatorStake memory)
    {   
        return pubkeyHashToStakeHistory[pubkeyHash][index];
    }

    function getMostRecentStakeByOperator(address operator) public view returns (OperatorStake memory) {
        bytes32 pubkeyHash = getOperatorPubkeyHash(operator);
        uint256 historyLength = pubkeyHashToStakeHistory[pubkeyHash].length;
        OperatorStake memory opStake;
        if (historyLength == 0) {
            return opStake;
        } else {
            opStake = pubkeyHashToStakeHistory[pubkeyHash][historyLength - 1];
            return opStake;
        }
    }

    function firstQuorumStakedByOperator(address operator) external view returns (uint96) {
        OperatorStake memory opStake = getMostRecentStakeByOperator(operator);
        return opStake.firstQuorumStake;
    }

    function secondQuorumStakedByOperator(address operator) external view returns (uint96) {
        OperatorStake memory opStake = getMostRecentStakeByOperator(operator);
        return opStake.secondQuorumStake;
    }

    function operatorStakes(address operator) public view returns (uint96, uint96) {
        OperatorStake memory opStake = getMostRecentStakeByOperator(operator);
        return (opStake.firstQuorumStake, opStake.secondQuorumStake);
    }

    function isRegistered(address operator) external view returns (bool) {
        (uint96 firstQuorumStake, uint96 secondQuorumStake) = operatorStakes(operator);
        return (firstQuorumStake > 0 || secondQuorumStake > 0);
    }

    function totalFirstQuorumStake() external view returns (uint96) {
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];
        return _totalStake.firstQuorumStake;
    }

    function totalSecondQuorumStake() external view returns (uint96) {
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];
        return _totalStake.secondQuorumStake;
    }

    function totalStake() external view returns (uint96, uint96) {
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];
        return (_totalStake.firstQuorumStake, _totalStake.secondQuorumStake);
    }

    function getLengthOfPubkeyHashStakeHistory(bytes32 pubkeyHash) external view returns (uint256) {
        return pubkeyHashToStakeHistory[pubkeyHash].length;
    }

    function getLengthOfPubkeyHashIndexHistory(bytes32 pubkeyHash) external view returns (uint256) {
        return pubkeyHashToIndexHistory[pubkeyHash].length;
    }

    function getLengthOfTotalStakeHistory() external view returns (uint256) {
        return totalStakeHistory.length;
    }

    function getLengthOfTotalOperatorsHistory() external view returns (uint256) {
        return totalOperatorsHistory.length;
    }

    function getTotalStakeFromIndex(uint256 index) external view returns (OperatorStake memory) {
        return totalStakeHistory[index];
    }

    /**
     @notice returns task number from when operator has been registered.
     */
    function getFromTaskNumberForOperator(address operator)
        external
        view
        returns (uint32)
    {
        return registry[operator].fromTaskNumber;
    }

    /**
     @notice returns block number from when operator has been registered.
     */
    function getFromBlockNumberForOperator(address operator)
        external
        view
        returns (uint32)
    {
        return registry[operator].fromBlockNumber;
    }

    function getOperatorDeregisterTime(address operator)
        external
        view
        returns (uint256)
    {
        return registry[operator].deregisterTime;
    }

    // number of operators of this service
    function numOperators() public view returns(uint64) {
        return uint64(operatorList.length);
    }

    // INTERNAL FUNCTIONS

    function _updateTotalOperatorsHistory() internal {
            // set the 'toBlockNumber' field on the last entry *so far* in 'totalOperatorsHistory' to the current block number
            totalOperatorsHistory[totalOperatorsHistory.length - 1].toBlockNumber = uint32(block.number);
            // push a new entry to 'totalOperatorsHistory', with 'index' field set equal to the new amount of operators
            OperatorIndex memory _totalOperators;
            _totalOperators.index = uint32(operatorList.length);
            totalOperatorsHistory.push(_totalOperators);
    }

    /**
     * Remove the operator from active status. Removes the operator with the given `pubkeyHash` from the `index` in `operatorList`,
     * updates operatorList and index histories, and performs other necessary updates for removing operator
     */
    function _removeRegistrant(bytes32 pubkeyHash, uint32 index) internal {
        // @notice Registrant must continue to serve until the latest time at which an active task expires. this info is used in challenges
        registry[msg.sender].serveUntil = repository.serviceManager().latestTime();
        // committing to not signing off on any more middleware tasks
        registry[msg.sender].active = IQuorumRegistry.Active.INACTIVE;
        registry[msg.sender].deregisterTime = block.timestamp;

        // gas saving by caching length here
        uint256 pubkeyHashToStakeHistoryLengthMinusOne = pubkeyHashToStakeHistory[pubkeyHash].length - 1;

        // determine current stakes
        OperatorStake memory currentStakes = pubkeyHashToStakeHistory[pubkeyHash][pubkeyHashToStakeHistoryLengthMinusOne];
        //set nextUpdateBlockNumber in current stakes
        pubkeyHashToStakeHistory[pubkeyHash][pubkeyHashToStakeHistoryLengthMinusOne].nextUpdateBlockNumber = uint32(block.number);

        /**
         @notice recording the information pertaining to change in stake for this operator in the history. operator stakes are set to 0 here.
         */
        pubkeyHashToStakeHistory[pubkeyHash].push(
            OperatorStake({
                // recording the current block number where the operator stake got updated 
                updateBlockNumber: uint32(block.number),
                // mark as 0 since the next update has not yet occurred
                nextUpdateBlockNumber: 0,
                // setting the operator's stakes to 0
                firstQuorumStake: 0,
                secondQuorumStake: 0
            })
        );

        // subtract the amounts staked by the operator that is getting deregistered from the total stake
        // copy latest totalStakes to memory
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];
        _totalStake.firstQuorumStake -= currentStakes.firstQuorumStake;
        _totalStake.secondQuorumStake -= currentStakes.secondQuorumStake;
        // update storage of total stake
        _recordTotalStakeUpdate(_totalStake);

        // store blockNumber at which operator index changed (stopped being applicable)
        pubkeyHashToIndexHistory[pubkeyHash][pubkeyHashToIndexHistory[pubkeyHash].length - 1].toBlockNumber = uint32(block.number);

        // remove the operator at `index` from the `operatorList`
        address swappedOperator = _popRegistrant(index);

        // Emit `Deregistration` event
        emit Deregistration(msg.sender, swappedOperator);
    }

    // Removes the registrant at the given `index` from the `operatorList`
    function _popRegistrant(uint32 index) internal returns (address swappedOperator) {
        // gas saving by caching length here
        uint256 operatorListLengthMinusOne = operatorList.length - 1;
        // Update index info for operator at end of list, if they are not the same as the removed operator
        if (index < operatorListLengthMinusOne){
            // get existing operator at end of list, and retrieve their pubkeyHash
            swappedOperator = operatorList[operatorListLengthMinusOne];
            Operator memory registrant = registry[swappedOperator];
            bytes32 pubkeyHash = registrant.pubkeyHash;
            // store blockNumber at which operator index changed
            // same operation as above except pubkeyHash is now different (since different operator)
            pubkeyHashToIndexHistory[pubkeyHash][pubkeyHashToIndexHistory[pubkeyHash].length - 1].toBlockNumber = uint32(block.number);
            // push new 'OperatorIndex' struct to operator's array of historical indices, with 'index' set equal to 'index' input
            OperatorIndex memory operatorIndex;
            operatorIndex.index = index;
            pubkeyHashToIndexHistory[pubkeyHash].push(operatorIndex);

            // move 'swappedOperator' into 'index' slot in operatorList (swapping them with removed operator)
            operatorList[index] = swappedOperator;
        }

        operatorList.pop();
        // Update totalOperatorsHistory
        _updateTotalOperatorsHistory();

        return swappedOperator;
    }

    // Adds the Operator `operator` with the given `pubkeyHash` to the `operatorList`
    function _addRegistrant(address operator, bytes32 pubkeyHash, OperatorStake memory _operatorStake, string calldata socket) internal {
        // store the Operator's info in mapping
        registry[operator] = Operator({
            pubkeyHash: pubkeyHash,
            id: nextOperatorId,
            index: numOperators(),
            active: IQuorumRegistry.Active.ACTIVE,
            fromTaskNumber: repository.serviceManager().taskNumber(),
            fromBlockNumber: uint32(block.number),
            serveUntil: 0,
            // extract the socket address
            socket: socket,
            deregisterTime: 0
        });

        // record the operator being registered and update the counter for operator ID
        operatorList.push(operator);
        unchecked {
            ++nextOperatorId;
        }

        // add the `updateBlockNumber` info
        _operatorStake.updateBlockNumber = uint32(block.number);
        // push the new stake for the operator to storage
        pubkeyHashToStakeHistory[pubkeyHash].push(_operatorStake);

        // record `operator`'s index in list of operators
        OperatorIndex memory operatorIndex;
        operatorIndex.index = uint32(operatorList.length - 1);
        pubkeyHashToIndexHistory[pubkeyHash].push(operatorIndex);

        // copy latest totalStakes to memory
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];
        _totalStake.firstQuorumStake += _operatorStake.firstQuorumStake;
        _totalStake.secondQuorumStake += _operatorStake.secondQuorumStake;
        // update storage of total stake
        _recordTotalStakeUpdate(_totalStake);

        // Update totalOperatorsHistory array
        _updateTotalOperatorsHistory();
    }

    // used inside of inheriting contracts to validate the registration of `operator` and find their `OperatorStake`
    function _registrationStakeEvaluation(address operator, uint8 operatorType) internal returns (OperatorStake memory) {
        require(
            registry[operator].active == IQuorumRegistry.Active.INACTIVE,
            "RegistryBase._registrationStakeEvaluation: Operator is already registered"
        );

        OperatorStake memory _operatorStake;

        // if first bit of operatorType is '1', then operator wants to be a validator for the first quorum
        if ((operatorType & 1) == 1) {
            _operatorStake.firstQuorumStake = uint96(weightOfOperator(operator, 0));
            // check if minimum requirement has been met
            if (_operatorStake.firstQuorumStake < nodeStakeFirstQuorum) {
                _operatorStake.firstQuorumStake = uint96(0);
            }
        }

        //if second bit of operatorType is '1', then operator wants to be a validator for the second quorum
        if ((operatorType & 2) == 2) {
            _operatorStake.secondQuorumStake = uint96(weightOfOperator(operator, 1));
            // check if minimum requirement has been met
            if (_operatorStake.secondQuorumStake < nodeStakeSecondQuorum) {
                _operatorStake.secondQuorumStake = uint96(0);
            }
        }

        require(
            _operatorStake.firstQuorumStake > 0 || _operatorStake.secondQuorumStake > 0,
            "RegistryBase._registrationStakeEvaluation: Must register as at least one type of validator"
        );

        return _operatorStake;
    }

    // Finds the updated stake for `operator`, stores it and records the update. **DOES NOT UPDATE `totalStake` IN ANY WAY** -- `totalStake` updates must be done elsewhere
    function _updateOperatorStake(address operator, bytes32 pubkeyHash, OperatorStake memory currentOperatorStake) internal returns (OperatorStake memory updatedOperatorStake) {            
        // determine new stakes
        updatedOperatorStake.updateBlockNumber = uint32(block.number);
        updatedOperatorStake.firstQuorumStake = weightOfOperator(operator, 0);
        updatedOperatorStake.secondQuorumStake = weightOfOperator(operator, 1);

        // check if minimum requirements have been met
        if (updatedOperatorStake.firstQuorumStake < nodeStakeFirstQuorum) {
            updatedOperatorStake.firstQuorumStake = uint96(0);
        }
        if (updatedOperatorStake.secondQuorumStake < nodeStakeSecondQuorum) {
            updatedOperatorStake.secondQuorumStake = uint96(0);
        }
        //set nextUpdateBlockNumber in prev stakes
        pubkeyHashToStakeHistory[pubkeyHash][pubkeyHashToStakeHistory[pubkeyHash].length - 1].nextUpdateBlockNumber = uint32(block.number);
        // push new stake to storage
        pubkeyHashToStakeHistory[pubkeyHash].push(updatedOperatorStake);

        emit StakeUpdate(
            operator,
            updatedOperatorStake.firstQuorumStake,
            updatedOperatorStake.secondQuorumStake,
            uint32(block.number),
            currentOperatorStake.updateBlockNumber
        );

        return (updatedOperatorStake);
    }

    // records that the `totalStake` is now equal to the input param @_totalStake
    function _recordTotalStakeUpdate(OperatorStake memory _totalStake) internal {
        _totalStake.updateBlockNumber = uint32(block.number);
        totalStakeHistory[totalStakeHistory.length - 1].nextUpdateBlockNumber = uint32(block.number);
        totalStakeHistory.push(_totalStake);
    }

    // verify that the `operator` is an active operator and that they've provided the correct `index`
    function _deregistrationCheck(address operator, uint32 index) internal view {
        require(
            registry[operator].active != IQuorumRegistry.Active.INACTIVE,
            "RegistryBase._deregistrationCheck: Operator is already registered"
        );

        require(
            operator == operatorList[index],
            "RegistryBase._deregistrationCheck: Incorrect index supplied"
        );
    }
}


