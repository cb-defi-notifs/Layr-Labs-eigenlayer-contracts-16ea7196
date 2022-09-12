// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "./RegistryBase.sol";
import "../interfaces/IECDSARegistry.sol";

// import "forge-std/Test.sol";

/**
 * @notice This contract is used for 
            - registering new operators 
            - committing to and finalizing de-registration as an operator 
            - updating the stakes of the operator
 */
// TODO: this contract has known concurrency issues with multiple updates to the 'stakes' object landing in quick succession -- need to evaluate potential solutions
contract ECDSARegistry is
    RegistryBase,
    IECDSARegistry
    // ,DSTest
{
    using BytesLib for bytes;

    /// @notice the block numbers at which the stake object was updated
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
        address indexed operator,
        bytes32 pubkeyHash
    );

    constructor(
        Repository _repository,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager,
        uint8 _NUMBER_OF_QUORUMS,
        uint256[] memory _quorumBips,
        StrategyAndWeightingMultiplier[] memory _ethStrategiesConsideredAndMultipliers,
        StrategyAndWeightingMultiplier[] memory _eigenStrategiesConsideredAndMultipliers
    )
        RegistryBase(
            _repository,
            _delegation,
            _investmentManager,
            _NUMBER_OF_QUORUMS,
            _quorumBips,
            _ethStrategiesConsideredAndMultipliers,
            _eigenStrategiesConsideredAndMultipliers
        )
    {
        // TODO: verify this initialization is correct
        bytes memory emptyBytes;
        _processStakeHashUpdate(keccak256(emptyBytes));
    }

    /**
     @notice called for registering as a operator
     */
    /**
     @param operatorType specifies whether the operator want to register as ETH staker or Eigen stake or both
     @param stakes is the calldata that contains the preimage of the current stakesHash
     @param socket is the socket address of the operator
     
     */ 
    function registerOperator(
        uint8 operatorType,
        address signingAddress,
        bytes calldata stakes,
        string calldata socket
    ) external virtual {        
        _registerOperator(msg.sender, signingAddress, operatorType, stakes, socket);

    }
    
    /**
     @param operator is the node who is registering to be a operator
     */
    function _registerOperator(
        address operator,
        address signingAddress,
        uint8 operatorType,
        bytes calldata stakes,
        string calldata socket
    ) internal {

        OperatorStake memory _operatorStake = _registrationStakeEvaluation(operator, registrantType);

        //bytes to add to the existing stakes object
        bytes memory dataToAppend = abi.encodePacked(operator, _operatorStake.ethStake, _operatorStake.eigenStake);

        // verify integrity of supplied 'stakes' data
        require(
            keccak256(stakes) == stakeHashes[stakeHashUpdates[stakeHashUpdates.length - 1]],
            "ECDSARegistry._registerOperator: Supplied stakes are incorrect"
        );

        // get current task number from ServiceManager
        uint32 currentTaskNumber = repository.serviceManager().taskNumber();

        // convert signingAddress to bytes32
        bytes32 pubkeyHash = bytes32(uint256(uint160(signingAddress)));

        // add the operator to the list of registrants and do accounting
        _addRegistrant(operator, pubkeyHash, _operatorStake, socket);
        
        {
            // store the updated meta-data in the mapping with the key being the current dump number
            /** 
             * @dev append the tuple (operator's address, operator's ETH deposit in EigenLayr)
             *      at the front of the list of tuples pertaining to existing operators. 
             *      Also, need to update the total ETH and/or EIGEN deposited by all operators.
             */
            _processStakeHashUpdate(keccak256(
                abi.encodePacked(
                    stakes.slice(0, stakes.length - 24),
                    // append at the end of list
                    dataToAppend,
                    // update the total ETH and EIGEN deposited
                    totalStakeHistory[totalStakeHistory.length - 1].ethStake,
                    totalStakeHistory[totalStakeHistory.length - 1].eigenStake
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
        // verify that the `msg.sender` is an active operator and that they've provided the correct `index`
        _deregistrationCheck(msg.sender, index);

        // verify integrity of supplied 'stakes' data
        require(
            keccak256(stakes) == stakeHashes[stakeHashUpdates[stakeHashUpdates.length - 1]],
            "ECDSARegistry._deregisterOperator: Supplied stakes are incorrect"
        );

        // Perform necessary updates for removing operator, including updating registrant list and index histories
        _removeRegistrant(registry[msg.sender].pubkeyHash, index);

        // placing the pointer at the starting byte of the tuple 
        /// @dev 44 bytes per operator: 20 bytes for address, 12 bytes for its ETH deposit, 12 bytes for its EIGEN deposit
        uint256 start = uint256(index * 44);
        // storage caching to save gas (less SLOADs)
        uint256 stakesLength = stakes.length;

        // scoped block helps prevent stack too deep
        {
            require(
                start < stakesLength - 68,
                "ECDSARegistry._deregisterOperator: Cannot point to total bytes"
            );
            require(
                stakes.toAddress(start) == msg.sender,
                "ECDSARegistry._deregisterOperator: index is incorrect"
            );
        }

        // find new stakes object, replacing deposit of the operator with updated deposit
        bytes memory updatedStakesArray = stakes
        // slice until just before the address bytes of the operator
        .slice(0, start)
            // concatenate the bytes pertaining to the tuples from rest of the middleware 
            // operators except the last 24 bytes that comprises of total ETH deposits and EIGEN deposits
            .concat(stakes.slice(start + 44, stakesLength - 24)
            // concatenate the updated deposits in the last 24 bytes
            .concat(
                abi.encodePacked(
                    (totalStakeHistory[totalStakeHistory.length - 1].ethStake),
                    (totalStakeHistory[totalStakeHistory.length - 1].eigenStake)
                )
            )
        );

        // store hash of 'stakes' and record that an update has occurred
        _processStakeHashUpdate(keccak256(updatedStakesArray));
    }

    /**
     * @notice Used for updating information on ETH and EIGEN deposits of DataLayr nodes. 
     */
    /**
     * @param stakes is the meta-data on the existing DataLayr nodes' addresses and 
     *        their ETH and EIGEN deposits. This param is in abi-encodedPacked form of the list of 
     *        the form 
     *          (dln1's operatorType, dln1's addr, dln1's ETH deposit, dln1's EIGEN deposit),
     *          (dln2's operatorType, dln2's addr, dln2's ETH deposit, dln2's EIGEN deposit), ...
     *          (sum of all nodes' ETH deposits, sum of all nodes' EIGEN deposits)
     *          where operatorType is a uint8 and all others are a uint96
     * @param operators are the DataLayr nodes whose information on their ETH and EIGEN deposits
     *        getting updated
     * @param indexes are the tuple positions whose corresponding ETH and EIGEN deposit is 
     *        getting updated  
     */ 
    function updateStakes(
        bytes calldata stakes,
        address[] memory operators,
        uint32[] memory indexes
    ) external {
        //provided 'stakes' must be preimage of last update's hash
        require(
            keccak256(stakes) ==
                stakeHashes[
                    stakeHashUpdates[stakeHashUpdates.length - 1]
                ],
            "ECDSARegistry.updateStakes: Stakes are incorrect"
        );

        uint256 operatorsLength = operators.length;
        require(
            indexes.length == operatorsLength,
            "ECDSARegistry.updateStakes: operator len and index len don't match"
        );

        // copy total stake to memory
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];

        // placeholders to be reused inside loop
        OperatorStake memory currentStakes;
        uint256 start;
        bytes32 pubkeyHash;
        // storage caching to save gas (less SLOADs)
        uint256 stakesLength = stakes.length;

        bytes memory updatedStakesArray = stakes;

        // iterating over all the tuples that are to be updated
        for (uint256 i = 0; i < operatorsLength; ) {
            // get operator's pubkeyHash
            pubkeyHash = registry[operators[i]].pubkeyHash;
            // fetch operator's existing stakes
            currentStakes = pubkeyHashToStakeHistory[pubkeyHash][pubkeyHashToStakeHistory[pubkeyHash].length - 1];
            // decrease _totalStake by operator's existing stakes
            _totalStake.ethStake -= currentStakes.ethStake;
            _totalStake.eigenStake -= currentStakes.eigenStake;

            // placing the pointer at the starting byte of the tuple 
            /// @dev 44 bytes per operator: 20 bytes for address, 12 bytes for its ETH deposit, 12 bytes for its EIGEN deposit
            start = uint256(indexes[i] * 44);

            // scoped block helps prevent stack too deep
            {
                require(
                    start < stakesLength - 68,
                    "ECDSARegistry.updateStakes: Cannot point to total bytes"
                );
                require(
                    stakes.toAddress(start) == operators[i],
                    "ECDSARegistry.updateStakes: index is incorrect"
                );
            }

            // update the stake for the i-th operator
            currentStakes = _updateOperatorStake(operators[i], pubkeyHash, currentStakes);

            // increase _totalStake by operator's updated stakes
            _totalStake.ethStake += currentStakes.ethStake;
            _totalStake.eigenStake += currentStakes.eigenStake;

            // find new stakes object, replacing deposit of the operator with updated deposit
            updatedStakesArray = updatedStakesArray
            // slice until just after the address bytes of the operator
            .slice(0, start + 20)
            // concatenate the updated ETH and EIGEN deposits
            .concat(abi.encodePacked(currentStakes.ethStake, currentStakes.eigenStake))
            // concatenate the bytes pertaining to the tuples from rest of the operators 
            // except the last 24 bytes that comprises of total ETH deposits
            .concat(stakes.slice(start + 44, stakesLength - 24));

            unchecked {
                ++i;
            }
        }

        // concatenate the updated total stakes in the last 24 bytes of stakes
        updatedStakesArray = updatedStakesArray
        .concat(
            abi.encodePacked(
                (_totalStake.ethStake),
                (_totalStake.eigenStake)
            )
        );

        // update storage of total stake
        _recordTotalStakeUpdate(_totalStake);

        // store hash of 'stakes' and record that an update has occurred
        _processStakeHashUpdate(keccak256(stakes));
    }

    // updates the stored stakeHash by pushing new entries to the `stakeHashes` and `stakeHashUpdates` arrays
    function _processStakeHashUpdate(bytes32 newStakeHash) internal {
        stakeHashes.push(newStakeHash);
        stakeHashUpdates.push(uint32(block.number));
    }

    /**
     @notice get hash of a historical stake object corresponding to a given index;
             called by checkSignatures in BLSSignatureChecker.sol.
     */
    function getCorrectStakeHash(uint256 index, uint32 blockNumber)
        external
        view
        returns (bytes32)
    {
        require(
            blockNumber >= stakeHashUpdates[index],
            "ECDSARegistry.getCorrectStakeHash: Index too recent"
        );

        // if not last update
        if (index != stakeHashUpdates.length - 1) {
            require(
                blockNumber < stakeHashUpdates[index + 1],
                "ECDSARegistry.getCorrectStakeHash: Not latest valid stakeHashUpdate"
            );
        }

        return stakeHashes[index];
    }

    function getStakeHashUpdatesLength() external view returns (uint256) {
        return stakeHashUpdates.length;
    }

    function getStakeHashesLength() external view returns (uint256) {
        return stakeHashes.length;
    }
}