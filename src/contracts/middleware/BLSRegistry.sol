// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./RegistryBase.sol";

import "ds-test/test.sol";

/**
 * @notice This contract is used for 
            - registering new operators 
            - committing to and finalizing de-registration as an operator 
            - updating the stakes of the operator
 */

contract BLSRegistry is
    RegistryBase
{
    using BytesLib for bytes;

    /// @notice the task numbers at which the aggregated pubkeys were updated
    uint32[] public apkUpdates;

    /**
     @notice list of keccak256(apk_x0, apk_x1, apk_y0, apk_y1) of operators, 
             this is updated whenever a new operator registers or deregisters
     */
    bytes32[] public apkHashes;

    /**
     @notice used for storing current aggregate public key
     */
    /** 
     @dev Initialized value is the generator of G2 group. It is necessary in order to do 
     addition in Jacobian coordinate system.
     */
    uint256[4] public apk;

    
    // EVENTS
    /**
     * @notice
     */
    event Registration(
        address indexed registrant,
        bytes32 pkHash,
        uint256[4] pk,
        uint32 apkHashIndex,
        bytes32 apkHash
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
        /** 
         @dev Initialized value is the generator of G2 group. It is necessary in order to do 
         addition in Jacobian coordinate system.
         */
        uint256[4] memory initApk = [G2x0, G2x1, G2y0, G2y1];
        // TODO: verify this initialization is correct
        _processApkUpdate(initApk);
    }

    /**
     @notice called for registering as a operator
     */
    /**
     @param registrantType specifies whether the operator want to register as ETH staker or Eigen stake or both
     @param data is the calldata that contains the coordinates for pubkey on G2 and signature on G1
     @param socket is the socket address of the operator
     
     */ 
    function registerOperator(
        uint8 registrantType,
        bytes calldata data,
        string calldata socket
    ) public virtual {        
        _registerOperator(msg.sender, registrantType, data, socket);
    }
    
    /**
     @param operator is the node who is registering to be a operator
     */
    function _registerOperator(
        address operator,
        uint8 registrantType,
        bytes calldata data,
        string calldata socket
    ) internal {

        OperatorStake memory _operatorStake = _registrationStakeEvaluation(operator, registrantType);

        /**
         @notice evaluate the new aggregated pubkey
         */
        uint256[4] memory newApk;
        uint256[4] memory pk;

        {

            // verify sig of public key and get pubkeyHash back, slice out compressed apk
            (pk[0], pk[1], pk[2], pk[3]) = BLS.verifyBLSSigOfPubKeyHash(data, operator, 164); 
            //verifyBLS(data, msg.sender, 164);
            
            // add pubkey to aggregated pukkey in Jacobian coordinates
            uint256[6] memory newApkJac = BLS.addJac([pk[0], pk[1], pk[2], pk[3], 1, 0], [apk[0], apk[1], apk[2], apk[3], 1, 0]);
            
            // convert back to Affine coordinates
            (newApk[0], newApk[1], newApk[2], newApk[3]) = BLS.jacToAff(newApkJac);
        }
        
        // getting pubkey hash 
        bytes32 pubkeyHash = keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3]));
        
        // addition doesn't work in this case 
        // our addition algorithm doesn't work
        require(pubkeyHash != apkHashes[apkHashes.length - 1], "BLSRegistry._registerOperator: Apk and pubkey cannot be the same");
        
        /**
         @notice some book-keeping for aggregated pubkey
         */
        // get current task number from ServiceManager
        uint32 currentTaskNumber = repository.serviceManager().taskNumber();

        // record the APK update and get the hash of the new APK
        bytes32 newApkHash = _processApkUpdate(newApk);

        /**
         @notice some book-keeping for recording info pertaining to the operator
         */
        // record the new stake for the operator in the storage
        _operatorStake.updateBlockNumber = uint32(block.number);
        pubkeyHashToStakeHistory[pubkeyHash].push(_operatorStake);
        
        // store the registrant's info in relation
        registry[operator] = Registrant({
            pubkeyHash: pubkeyHash,
            id: nextRegistrantId,
            index: numRegistrants(),
            active: IQuorumRegistry.Active.ACTIVE,
            fromTaskNumber: currentTaskNumber,
            fromBlockNumber: uint32(block.number),
            serveUntil: 0,
            // extract the socket address
            socket: socket,
            deregisterTime: 0
        });

        // add the operator to the list of registrants and do accounting
        _pushRegistrant(operator, pubkeyHash, _operatorStake);
            
        emit Registration(operator, pubkeyHash, pk, uint32(apkHashes.length)-1, newApkHash);
    }

    /**
      @notice Used by an operator to de-register itself from providing service to the middleware.
     */
    /** 
      @param pubkeyToRemoveAff is the sender's pubkey in affine coordinates
     */
    function deregisterOperator(uint256[4] memory pubkeyToRemoveAff, uint32 index) external virtual returns (bool) {
        _deregisterOperator(pubkeyToRemoveAff, index);
        return true;
    }

    function _deregisterOperator(uint256[4] memory pubkeyToRemoveAff, uint32 index) internal {
        // verify that the `msg.sender` is an active operator and that they've provided the correct `index`
        _deregistrationCheck(msg.sender, index);
        
        /**
         @notice verify that the sender is a operator that is doing deregistration for itself 
         */
        // get operator's stored pubkeyHash
        bytes32 pubkeyHash = registry[msg.sender].pubkeyHash;
        bytes32 pubkeyHashFromInput = keccak256(
            abi.encodePacked(
                pubkeyToRemoveAff[0],
                pubkeyToRemoveAff[1],
                pubkeyToRemoveAff[2],
                pubkeyToRemoveAff[3]
            )
        );
        // verify that it matches the 'pubkeyToRemoveAff' input
        require(pubkeyHash == pubkeyHashFromInput, "BLSRegistry._deregisterOperator: pubkey input does not match stored pubkeyHash");

        // Perform necessary updates for removing operator, including updating registrant list and index histories
        _removeOperator(pubkeyHash, index);

        /**
         @notice update the aggregated public key of all registered operators and record
                 this update in history
         */
        // get existing aggregate public key
        uint256[4] memory pk = apk;
        // remove signer's pubkey from aggregate public key
        (pk[0], pk[1], pk[2], pk[3]) = BLS.removePubkeyFromAggregate(pubkeyToRemoveAff, pk);

        // record the APK update
        _processApkUpdate(pk);
    }

    /**
     * @notice Used for updating information on ETH and EIGEN deposits of nodes.
     */
    /**
     * @param operators are the nodes whose information on their ETH and EIGEN deposits
     *        getting updated
     */
    function updateStakes(address[] calldata operators) external {
        // copy total stake to memory
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];

        uint256 operatorsLength = operators.length;
        // iterating over all the tuples that are to be updated
        for (uint256 i = 0; i < operatorsLength; ) {

            // update the stake for the i-th operator
            (_totalStake, ) = _updateOperatorStake(operators[i], _totalStake);

            unchecked {
                ++i;
            }
        }

        // update storage of total stake
        _recordTotalStakeUpdate(_totalStake);
    }

    // updates the stored APK to `newApk`, calculates its hash, and pushes new entries to the `apkUpdates` and `apkHashes` arrays
    // returns the hash of `newApk
    function _processApkUpdate(uint256[4] memory newApk) internal returns (bytes32) {
        // update stored aggregate public key
        apk = newApk;

        // store the current block number in which the aggregated pubkey is being updated 
        apkUpdates.push(uint32(block.number));
        
        //store the hash of aggregate pubkey
        bytes32 newApkHash = keccak256(abi.encodePacked(newApk[0], newApk[1], newApk[2], newApk[3]));
        apkHashes.push(newApkHash);
        return newApkHash;
    }

    /**
     @notice get hash of a historical aggregated public key corresponding to a given index;
             called by checkSignatures in SignatureChecker.sol.
     */
    function getCorrectApkHash(uint256 index, uint32 blockNumber)
        public
        view
        returns (bytes32)
    {
        require(
            blockNumber >= apkUpdates[index],
            "BLSRegistry.getCorrectApkHash: Index too recent"
        );

        // if not last update
        if (index != apkUpdates.length - 1) {
            require(
                blockNumber < apkUpdates[index + 1],
                "BLSRegistry.getCorrectApkHash: Not latest valid apk update"
            );
        }

        return apkHashes[index];
    }

    function getApkUpdatesLength() public view returns (uint256) {
        return apkUpdates.length;
    }

    function getApkHashesLength() external view returns (uint256) {
        return apkHashes.length;
    }
}


