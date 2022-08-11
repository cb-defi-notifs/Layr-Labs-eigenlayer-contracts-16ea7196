// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IServiceManager.sol";
import "../interfaces/IQuorumRegistry.sol";
import "../libraries/BytesLib.sol";
import "./Repository.sol";
import "./VoteWeigherBase.sol";
import "../libraries/BLS.sol";

// import "ds-test/test.sol";

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

    // CONSTANTS
    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId, address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant REGISTRATION_TYPEHASH =
        keccak256(
            "Registration(address operator,address registrationContract,uint256 expiry)"
        );

    /// @notice EIP-712 Domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    uint128 public nodeEthStake = 1 wei;
    uint128 public nodeEigenStake = 1 wei;
    
    /// @notice a sequential counter that is incremented whenver new operator registers
    uint32 public nextRegistrantId;

    /// @notice used for storing Registrant info on each operator while registration
    mapping(address => Registrant) public registry;

    /// @notice used for storing the list of current and past registered operators 
    address[] public registrantList;

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
        uint96 ethStake,
        uint96 eigenStake,
        uint256 updateNumber,
        uint32 updateBlockNumber,
        uint32 prevUpdateBlockNumber
    );

    event StakeUpdate(
        address operator,
        uint96 ethStake,
        uint96 eigenStake,
        uint32 updateBlockNumber,
        uint32 prevUpdateBlockNumber
    );

    event Deregistration(
        address registrant,
        address swapped
    );

    constructor(
        Repository _repository,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager,
        uint8 _NUMBER_OF_QUORUMS,
        StrategyAndWeightingMultiplier[] memory _ethStrategiesConsideredAndMultipliers,
        StrategyAndWeightingMultiplier[] memory _eigenStrategiesConsideredAndMultipliers
    )
        VoteWeigherBase(
            _repository,
            _delegation,
            _investmentManager,
            _NUMBER_OF_QUORUMS
        )
    {
        //apk_0 = g2Gen
        // initialize the DOMAIN_SEPARATOR for signatures
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(DOMAIN_TYPEHASH, bytes("EigenLayr"), block.chainid, address(this))
        );
        // push an empty OperatorStake struct to the total stake history
        OperatorStake memory _totalStake;
        totalStakeHistory.push(_totalStake);

        // push an empty OperatorIndex struct to the total operators history
        OperatorIndex memory _totalOperators;
        totalOperatorsHistory.push(_totalOperators);

        _addStrategiesConsideredAndMultipliers(0, _ethStrategiesConsideredAndMultipliers);
        _addStrategiesConsideredAndMultipliers(1, _eigenStrategiesConsideredAndMultipliers);
    }
    
    /*
     looks up the `operator`'s index in the dynamic array `registrantList` at the specified `blockNumber`.
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

    function setNodeEigenStake(uint128 _nodeEigenStake)
        external
        onlyRepositoryGovernance
    {
        nodeEigenStake = _nodeEigenStake;
    }

    function setNodeEthStake(uint128 _nodeEthStake)
        external
        onlyRepositoryGovernance
    {
        nodeEthStake = _nodeEthStake;
    }

    /// @notice returns the unique ID of the specified operator 
    function getOperatorId(address operator) external view returns (uint32) {
        return registry[operator].id;
    }


    /// @notice returns the active status for the specified operator
    function getOperatorType(address operator) external view returns (uint8) {
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
            opStake = pubkeyHashToStakeHistory[pubkeyHash][pubkeyHashToStakeHistory[pubkeyHash].length - 1];
            return opStake;
        }
    }

    function ethStakedByOperator(address operator) external view returns (uint96) {
        OperatorStake memory opStake = getMostRecentStakeByOperator(operator);
        return opStake.ethStake;
    }

    function eigenStakedByOperator(address operator) external view returns (uint96) {
        OperatorStake memory opStake = getMostRecentStakeByOperator(operator);
        return opStake.eigenStake;
    }

    function operatorStakes(address operator) public view returns (uint96, uint96) {
        OperatorStake memory opStake = getMostRecentStakeByOperator(operator);
        return (opStake.ethStake, opStake.eigenStake);
    }

    function isRegistered(address operator) external view returns (bool) {
        (uint96 ethStake, uint96 eigenStake) = operatorStakes(operator);
        return (ethStake > 0 || eigenStake > 0);
    }

    function totalEthStaked() external view returns (uint96) {
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];
        return _totalStake.ethStake;
    }

    function totalEigenStaked() external view returns (uint96) {
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];
        return _totalStake.eigenStake;
    }

    function totalStake() external view returns (uint96, uint96) {
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];
        return (_totalStake.ethStake, _totalStake.eigenStake);
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

    function getOperatorStatus(address operator) external view returns(uint8) {
        return registry[operator].active;
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

    // number of registrants of this service
    function numRegistrants() public view returns (uint64) {
        return uint64(registrantList.length);
    }

    // INTERNAL FUNCTIONS

    function _updateTotalOperatorsHistory() internal {
            // set the 'toBlockNumber' field on the last entry *so far* in 'totalOperatorsHistory' to the current block number
            totalOperatorsHistory[totalOperatorsHistory.length - 1].toBlockNumber = uint32(block.number);
            // push a new entry to 'totalOperatorsHistory', with 'index' field set equal to the new amount of operators
            OperatorIndex memory _totalOperators;
            _totalOperators.index = uint32(registrantList.length);
            totalOperatorsHistory.push(_totalOperators);
    }

    // Removes the registrant with the given pubkeyHash from the index in registrantList
    function _popRegistrant(bytes32 pubkeyHash, uint32 index) internal returns (address) {
        // gas saving by caching lengths here
        uint256 pubkeyHashToStakeHistoryLength = pubkeyHashToStakeHistory[pubkeyHash].length;
        uint256 totalStakeHistoryLengthMinusOne = totalStakeHistory.length - 1;
        uint256 registrantListLengthMinusOne = registrantList.length - 1;

        // determine current stakes
        OperatorStake memory currentStakes = pubkeyHashToStakeHistory[pubkeyHash][pubkeyHashToStakeHistoryLength - 1];

        /**
         @notice recording the information pertaining to change in stake for this operator in the history
         */
        // determine new stakes
        OperatorStake memory newStakes;
        // recording the current task number where the operator stake got updated 
        newStakes.updateBlockNumber = uint32(block.number);

        // setting total staked ETH for the operator to 0
        newStakes.ethStake = uint96(0);
        // setting total staked Eigen for the operator to 0
        newStakes.eigenStake = uint96(0);

        //set next task number in prev stakes -- we use `pubkeyHashToStakeHistoryLength` here since we've pushed a new entry, so this is now the last index
        pubkeyHashToStakeHistory[pubkeyHash][pubkeyHashToStakeHistoryLength].nextUpdateBlockNumber = uint32(block.number);

        // push new stake to storage
        pubkeyHashToStakeHistory[pubkeyHash].push(newStakes);

        /**
         @notice  update info on ETH and Eigen staked with the middleware
         */
        // subtract the staked Eigen and ETH of the operator that is getting deregistered from total stake
        // copy total stake to memory
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistoryLengthMinusOne];
        _totalStake.ethStake -= currentStakes.ethStake;
        _totalStake.eigenStake -= currentStakes.eigenStake;
        _totalStake.updateBlockNumber = uint32(block.number);
        totalStakeHistory[totalStakeHistoryLengthMinusOne].nextUpdateBlockNumber = uint32(block.number);
        totalStakeHistory.push(_totalStake);

        // Update index info for old operator
        // store blockNumber at which operator index changed (stopped being applicable)
        pubkeyHashToIndexHistory[pubkeyHash][pubkeyHashToIndexHistory[pubkeyHash].length - 1].toBlockNumber = uint32(block.number);

        address swappedOperator;
        // Update index info for operator at end of list, if they are not the same as the removed operator
        if (index < registrantListLengthMinusOne){
            // get existing operator at end of list, and retrieve their pubkeyHash
            swappedOperator = registrantList[registrantListLengthMinusOne];
            Registrant memory registrant = registry[swappedOperator];
            pubkeyHash = registrant.pubkeyHash;

            // store blockNumber at which operator index changed
            // same operation as above except pubkeyHash is now different (since different registrant)
            pubkeyHashToIndexHistory[pubkeyHash][pubkeyHashToIndexHistory[pubkeyHash].length - 1].toBlockNumber = uint32(block.number);
            // push new 'OperatorIndex' struct to operator's array of historical indices, with 'index' set equal to 'index' input
            OperatorIndex memory operatorIndex;
            operatorIndex.index = index;
            pubkeyHashToIndexHistory[pubkeyHash].push(operatorIndex);

            // move 'swappedOperator' into 'index' slot in registrantList (swapping them with removed operator)
            registrantList[index] = swappedOperator;
        }

        registrantList.pop();
        // Update totalOperatorsHistory
        _updateTotalOperatorsHistory();
        
        //return address of operator whose index has changed
        return swappedOperator;
    }

    // Adds the registrant `operator` with the given `pubkeyHash` to the `registrantList`
    function _pushRegistrant(address operator, bytes32 pubkeyHash) internal {
        // record the operator being registered
        registrantList.push(operator);

        // record operator's index in list of operators
        OperatorIndex memory operatorIndex;
        operatorIndex.index = uint32(registrantList.length - 1);
        pubkeyHashToIndexHistory[pubkeyHash].push(operatorIndex);

        // update the counter for registrant ID
        unchecked {
            ++nextRegistrantId;
        }
    }

    // used inside of inheriting contracts to validate the registration of `operator` and find their `OperatorStake`
    function _registrationStakeEvaluation(address operator, uint8 registrantType) internal returns (OperatorStake memory) {
        require(
            registry[operator].active == 0,
            "_registrationStakeEvaluation._registrationStakeEvaluation: Operator is already registered"
        );

        OperatorStake memory _operatorStake;

        // if first bit of registrantType is '1', then operator wants to be an ETH validator
        if ((registrantType & 1) == 1) {
            // if operator want to be an "ETH" validator, check that they meet the
            // minimum requirements on how much ETH it must deposit
            _operatorStake.ethStake = uint96(weightOfOperator(operator, 0));
            require(
                _operatorStake.ethStake >= nodeEthStake,

                "_registrationStakeEvaluation._registrationStakeEvaluation: Not enough eth value staked"
            );
        }

        //if second bit of registrantType is '1', then operator wants to be an EIGEN validator
        if ((registrantType & 2) == 2) {
            // if operator want to be an "Eigen" validator, check that they meet the
            // minimum requirements on how much Eigen it must deposit
            _operatorStake.eigenStake = uint96(weightOfOperator(operator, 1));
            require(
                _operatorStake.eigenStake >= nodeEigenStake,

                "_registrationStakeEvaluation._registrationStakeEvaluation: Not enough eigen staked"
            );
        }

        require(
            _operatorStake.ethStake > 0 || _operatorStake.eigenStake > 0,

            "_registrationStakeEvaluation._registrationStakeEvaluation: Must register as at least one type of validator"
        );

        return _operatorStake;
    }

    // update total Eigen and ETH that are being employed by the middleware for securing tasks
    function _addToTotalStake(uint96 ethStakeToAdd, uint96 eigenStakeToAdd) internal returns (OperatorStake memory) {
            OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];
            _totalStake.ethStake += ethStakeToAdd;
            _totalStake.eigenStake += eigenStakeToAdd;
            _totalStake.updateBlockNumber = uint32(block.number);
            // linking with the most recent stake record in the past
            totalStakeHistory[totalStakeHistory.length - 1].nextUpdateBlockNumber = uint32(block.number);
            totalStakeHistory.push(_totalStake);
            return _totalStake;
    }

    // Finds the updated stake for `operator`, stores it and records the update. Calculates the change to `_totalStake`, but **DOES NOT UPDATE THE `totalStake` STORAGE SLOT**
    function _updateOperatorStake(address operator, OperatorStake memory _totalStake) internal returns (OperatorStake memory, OperatorStake memory newStakes) {
            // get operator's pubkeyHash
            bytes32 pubkeyHash = registry[operator].pubkeyHash;
            // determine current stakes
            OperatorStake memory currentStakes = pubkeyHashToStakeHistory[
                pubkeyHash
            ][pubkeyHashToStakeHistory[pubkeyHash].length - 1];

            // determine new stakes
            newStakes.updateBlockNumber = uint32(block.number);
            newStakes.ethStake = weightOfOperator(operator, 0);
            newStakes.eigenStake = weightOfOperator(operator, 1);

            // check if minimum requirements have been met
            if (newStakes.ethStake < nodeEthStake) {
                newStakes.ethStake = uint96(0);
            }
            if (newStakes.eigenStake < nodeEigenStake) {
                newStakes.eigenStake = uint96(0);
            }
            //set nextUpdateBlockNumber in prev stakes
            pubkeyHashToStakeHistory[pubkeyHash][
                pubkeyHashToStakeHistory[pubkeyHash].length - 1
            ].nextUpdateBlockNumber = uint32(block.number);
            // push new stake to storage
            pubkeyHashToStakeHistory[pubkeyHash].push(newStakes);

            // calculate the change to _totalStake
            _totalStake.ethStake = _totalStake.ethStake + newStakes.ethStake - currentStakes.ethStake;
            _totalStake.eigenStake = _totalStake.eigenStake + newStakes.eigenStake - currentStakes.eigenStake;

            emit StakeUpdate(
                operator,
                newStakes.ethStake,
                newStakes.eigenStake,
                uint32(block.number),
                currentStakes.updateBlockNumber
            );

            return (_totalStake, newStakes);
    }
}


