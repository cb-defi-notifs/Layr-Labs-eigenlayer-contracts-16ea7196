// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./RegistryBase.sol";

// import "ds-test/test.sol";

/**
 * @notice This contract is used for 
            - registering new operators 
            - committing to and finalizing de-registration as an operator 
            - updating the stakes of the operator
 */

contract ECDSARegistry is
    RegistryBase
    // ,DSTest
{
    using BytesLib for bytes;

    /// @notice the taskNumbers at which the stake object was updated
    uint32[] public stakeHashUpdates;

    /**
     @notice list of keccak256(stakes) of operators, 
             this is updated whenever a new operator registers or deregisters
     */
    bytes32[] public stakeHashes;

    // EVENTS
    /**
     * @notice
     */
    event Registration(
        address indexed registrant,
        bytes32 pubkeyHash
    );

    constructor(
        Repository _repository,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager,
        uint8 _NUMBER_OF_QUORUMS,
        StrategyAndWeightingMultiplier[] memory _ethStrategiesConsideredAndMultipliers,
        StrategyAndWeightingMultiplier[] memory _eigenStrategiesConsideredAndMultipliers
    )
        RegistryBase(
            _repository,
            _delegation,
            _investmentManager,
            _NUMBER_OF_QUORUMS,
            _ethStrategiesConsideredAndMultipliers,
            _eigenStrategiesConsideredAndMultipliers
        )
    {
        // TODO: verify this initialization is correct
        stakeHashUpdates.push(0);
    }

    /**
     @notice called for registering as a operator
     */
    /**
     @param registrantType specifies whether the operator want to register as ETH staker or Eigen stake or both
     @param stakes is the calldata that contains the preimage of the current stakesHash
     @param socket is the socket address of the operator
     
     */ 
    function registerOperator(
        uint8 registrantType,
        address signingAddress,
        bytes calldata stakes,
        string calldata socket
    ) public virtual {        
        _registerOperator(msg.sender, signingAddress, registrantType, stakes, socket);
    }
    
    /**
     @param operator is the node who is registering to be a operator
     */
    function _registerOperator(
        address operator,
        address signingAddress,
        uint8 registrantType,
        bytes calldata stakes,
        string calldata socket
    ) internal {

        OperatorStake memory _operatorStake = _registrationStakeEvaluation(operator, registrantType);

        //bytes to add to the existing stakes object
        bytes memory dataToAppend = abi.encodePacked(operator, _operatorStake.ethStake, _operatorStake.eigenStake);

        // verify integrity of supplied 'stakes' data
        require(
            keccak256(stakes) == stakeHashes[stakeHashUpdates[stakeHashUpdates.length - 1]],
            "Supplied stakes are incorrect"
        );

        // get current task number from ServiceManager
        uint32 currentTaskNumber = IServiceManager(address(repository.serviceManager())).taskNumber();

        /**
         @notice some book-keeping for recording info pertaining to the operator
         */
        // record the new stake for the operator in the storage
        _operatorStake.updateBlockNumber = uint32(block.number);
        bytes32 pubkeyHash = bytes32(uint256(uint160(signingAddress)));
        pubkeyHashToStakeHistory[pubkeyHash].push(_operatorStake);

        // store the registrant's info
        registry[operator] = Registrant({
            pubkeyHash: pubkeyHash,
            id: nextRegistrantId,
            index: numRegistrants(),
            active: registrantType,
            fromTaskNumber: currentTaskNumber,
            fromBlockNumber: uint32(block.number),
            serveUntil: 0,
            // extract the socket address
            socket: socket,
            deregisterTime: 0
        });

        // add the operator to the list of registrants and do accounting
        _pushRegistrant(operator, pubkeyHash);

        // Update totalOperatorsHistory
        _updateTotalOperatorsHistory();
        
        {
            /**
            @notice some book-keeping for recoding updated total stake
            */
            OperatorStake memory _totalStake = _addToTotalStake(_operatorStake.ethStake, _operatorStake.eigenStake);

            // store the updated meta-data in the mapping with the key being the current dump number
            /** 
             * @dev append the tuple (operator's address, operator's ETH deposit in EigenLayr)
             *      at the front of the list of tuples pertaining to existing operators. 
             *      Also, need to update the total ETH and/or EIGEN deposited by all operators.
             */
            stakeHashes.push(keccak256(
                abi.encodePacked(
                    stakes.slice(0, stakes.length - 24),
                    // append at the end of list
                    dataToAppend,
                    // update the total ETH and EIGEN deposited
                    _totalStake.ethStake,
                    _totalStake.eigenStake
                )
            ));
        }

        emit StakeAdded(operator, _operatorStake.ethStake, _operatorStake.eigenStake, stakeHashUpdates.length, currentTaskNumber, stakeHashUpdates[stakeHashUpdates.length - 1]);
        emit Registration(operator, pubkeyHash);
    }

    /**
      @notice Used by an operator to de-register itself from providing service to the middleware.
     */
    /** 
      @param stakes is the calldata that contains the preimage of the current stakesHash
     */
    function deregisterOperator(bytes calldata stakes, uint32 index) external virtual returns (bool) {
        _deregisterOperator(stakes, index);
        return true;
    }

    function _deregisterOperator(bytes calldata stakes, uint32 index) internal {
        require(
            registry[msg.sender].active > 0,
            "Operator is already registered"
        );

        require(
            msg.sender == registrantList[index],
            "Incorrect index supplied"
        );

        // verify integrity of supplied 'stakes' data
        require(
            keccak256(stakes) == stakeHashes[stakeHashUpdates[stakeHashUpdates.length - 1]],
            "Supplied stakes are incorrect"
        );

        // must continue to serve until the latest time at which an active task expires
        /**
         @notice this info is used in challenges
         */
        registry[msg.sender].serveUntil = (repository.serviceManager()).latestTime();

        // committing to not signing off on any more data that is being asserted into DataLayr
        registry[msg.sender].active = 0;

        registry[msg.sender].deregisterTime = block.timestamp;
        
        /**
         @notice verify that the sender is a operator that is doing deregistration for itself 
         */
        // get operator's stored pubkeyHash
        bytes32 pubkeyHash = registry[msg.sender].pubkeyHash;

        // determine current stakes
        OperatorStake memory currentStakes = pubkeyHashToStakeHistory[
            pubkeyHash
        ][pubkeyHashToStakeHistory[pubkeyHash].length - 1];

        {
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

            //set nextUpdateBlockNumber in prev stakes
            pubkeyHashToStakeHistory[pubkeyHash][
                pubkeyHashToStakeHistory[pubkeyHash].length - 1
            ].nextUpdateBlockNumber = uint32(block.number); 

            // push new stake to storage
            pubkeyHashToStakeHistory[pubkeyHash].push(newStakes);
        }

        // Update registrant list and update index histories
        address swappedOperator = _popRegistrant(pubkeyHash,index);
        // event was moved up (from end of function) to solve 'stack too deep' when finding new stakes object
        emit Deregistration(msg.sender, swappedOperator);

        /**
         @notice  update info on ETH and Eigen staked with the middleware
         */
        // subtract the staked Eigen and ETH of the operator that is getting deregistered from total stake
        // copy total stake to memory
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];
        _totalStake.ethStake -= currentStakes.ethStake;
        _totalStake.eigenStake -= currentStakes.eigenStake;
        _totalStake.updateBlockNumber = uint32(block.number);
        totalStakeHistory[totalStakeHistory.length - 1].nextUpdateBlockNumber = uint32(block.number);
        totalStakeHistory.push(_totalStake);

        // update stakeHash
        stakeHashUpdates.push(uint32(block.number));

        // placing the pointer at the starting byte of the tuple 
        /// @dev 44 bytes per operator: 20 bytes for address, 12 bytes for its ETH deposit, 12 bytes for its EIGEN deposit
        uint256 start = uint256(index * 44);
        require(start < stakes.length - 68, "Cannot point to total bytes");
        require(
            stakes.toAddress(start) == msg.sender,
            "index is incorrect"
        );

        // find new stakes object, replacing deposit of the operator with updated deposit
        bytes memory updatedStakesArray = stakes
        // slice until just before the address bytes of the operator
        .slice(0, start)
            // concatenate the bytes pertaining to the tuples from rest of the middleware 
            // operators except the last 24 bytes that comprises of total ETH deposits and EIGEN deposits
            .concat(stakes.slice(start + 44, stakes.length - 24)
        );
// TODO: updating 'stake' was split into two actions to solve 'stack too deep' error -- but it should be possible to fix this
        updatedStakesArray = updatedStakesArray            
            // concatenate the updated deposits in the last 24 bytes
            .concat(
                abi.encodePacked(
                    (_totalStake.ethStake),
                    (_totalStake.eigenStake)
                )
        );

        // store hash of 'stakes'
        stakeHashes.push(keccak256(updatedStakesArray));
    }

    /**
     * @notice Used for updating information on ETH and EIGEN deposits of DataLayr nodes. 
     */
    /**
     * @param stakes is the meta-data on the existing DataLayr nodes' addresses and 
     *        their ETH and EIGEN deposits. This param is in abi-encodedPacked form of the list of 
     *        the form 
     *          (dln1's registrantType, dln1's addr, dln1's ETH deposit, dln1's EIGEN deposit),
     *          (dln2's registrantType, dln2's addr, dln2's ETH deposit, dln2's EIGEN deposit), ...
     *          (sum of all nodes' ETH deposits, sum of all nodes' EIGEN deposits)
     *          where registrantType is a uint8 and all others are a uint96
     * @param operators are the DataLayr nodes whose information on their ETH and EIGEN deposits
     *        getting updated
     * @param indexes are the tuple positions whose corresponding ETH and EIGEN deposit is 
     *        getting updated  
     */ 
    function updateStakes(
        bytes calldata stakes,
        address[] memory operators,
        uint32[] memory indexes
    ) public {
        //provided 'stakes' must be preimage of last update's hash
        require(
            keccak256(stakes) ==
                stakeHashes[
                    stakeHashUpdates[stakeHashUpdates.length - 1]
                ],
            "Stakes are incorrect"
        );

        uint256 operatorsLength = operators.length;
        require(
            indexes.length == operatorsLength,
            "operator len and index len don't match"
        );

        // copy total stake to memory
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];

        bytes memory updatedStakesArray = stakes;

        // iterating over all the tuples that are to be updated
        for (uint256 i = 0; i < operatorsLength; ) {

            // placing the pointer at the starting byte of the tuple 
            /// @dev 44 bytes per operator: 20 bytes for address, 12 bytes for its ETH deposit, 12 bytes for its EIGEN deposit
            uint256 start = uint256(indexes[i] * 44);

            require(start < stakes.length - 68, "Cannot point to total bytes");

            require(
                stakes.toAddress(start) == operators[i],
                "index is incorrect"
            );

            // get operator's pubkeyHash
            bytes32 pubkeyHash = registry[operators[i]].pubkeyHash;
            // determine current stakes
            OperatorStake memory currentStakes = pubkeyHashToStakeHistory[
                pubkeyHash
            ][pubkeyHashToStakeHistory[pubkeyHash].length - 1];

            // determine new stakes
            OperatorStake memory newStakes;

            newStakes.updateBlockNumber = uint32(block.number);
            newStakes.ethStake = weightOfOperator(operators[i], 0);
            newStakes.eigenStake = weightOfOperator(operators[i], 1);

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

            /**
             * update total Eigen and ETH that are being employed by the operator for securing
             * the queries from middleware via EigenLayr
             */
            _totalStake.ethStake = _totalStake.ethStake + newStakes.ethStake - currentStakes.ethStake;
            _totalStake.eigenStake = _totalStake.eigenStake + newStakes.eigenStake - currentStakes.eigenStake;

            // find new stakes object, replacing deposit of the operator with updated deposit
            updatedStakesArray = updatedStakesArray
            // slice until just after the address bytes of the operator
            .slice(0, start + 20)
            // concatenate the updated ETH and EIGEN deposits
            .concat(abi.encodePacked(newStakes.ethStake, newStakes.eigenStake));
//TODO: updating 'stake' was split into two actions to solve 'stack too deep' error -- but it should be possible to fix this
            updatedStakesArray = updatedStakesArray
            // concatenate the bytes pertaining to the tuples from rest of the operators 
            // except the last 24 bytes that comprises of total ETH deposits
            .concat(stakes.slice(start + 44, stakes.length - 24));

            emit StakeUpdate(
                operators[i],
                newStakes.ethStake,
                newStakes.eigenStake,
                uint32(block.number),
                currentStakes.updateBlockNumber
            );
            unchecked {
                ++i;
            }
        }

        // concatenate the updated deposits in the last 24 bytes,
        updatedStakesArray = updatedStakesArray
        .concat(
            abi.encodePacked(
                (_totalStake.ethStake),
                (_totalStake.eigenStake)
            )
        );

        // update storage of total stake
        _totalStake.updateBlockNumber = uint32(block.number);
        totalStakeHistory[totalStakeHistory.length - 1].nextUpdateBlockNumber = uint32(block.number);
        totalStakeHistory.push(_totalStake);

        stakeHashes.push(keccak256(stakes));
    }

    /**
     @notice get hash of a historical stake object corresponding to a given index;
             called by checkSignatures in BLSSignatureChecker.sol.
     */
    function getCorrectStakeHash(uint256 index, uint32 blockNumber)
        public
        view
        returns (bytes32)
    {
        require(
            blockNumber >= stakeHashUpdates[index],
            "Index too recent"
        );

        // if not last update
        if (index != stakeHashUpdates.length - 1) {
            require(
                blockNumber < stakeHashUpdates[index + 1],
                "Not latest valid stakeHashUpdate"
            );
        }

        return stakeHashes[index];
    }

    function getStakeHashUpdatesLength() public view returns (uint256) {
        return stakeHashUpdates.length;
    }

    function getStakeHashesLength() external view returns (uint256) {
        return stakeHashes.length;
    }
}