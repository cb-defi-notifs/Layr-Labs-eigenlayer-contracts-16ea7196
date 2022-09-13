// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "./RegistryBase.sol";
import "../interfaces/IBLSRegistry.sol";

import "forge-std/Test.sol";

/**
 * @notice This contract is used for 
            - registering new operators 
            - committing to and finalizing de-registration as an operator 
            - updating the stakes of the operator
 */

contract BLSRegistry is
    RegistryBase,
    IBLSRegistry
{
    using BytesLib for bytes;

    /// @notice the task numbers at which the aggregated pubkeys were updated
    uint32[] public apkUpdates;

    /**
     * @notice list of keccak256(apk_x0, apk_x1, apk_y0, apk_y1) of operators, 
     *        this is updated whenever a new operator registers or deregisters
     */
    bytes32[] public apkHashes;

    /**
     * @notice used for storing current aggregate public key
     * @dev Initialized value is the generator of G2 group. It is necessary in order to do 
     *      addition in Jacobian coordinate system.
     */
    uint256[4] public apk;
    
    // EVENTS
    /**
     * @notice Emitted upon the registration of a new operator for the middleware
     * @param operator Address of the new operator
     * @param pkHash The keccak256 hash of the operator's public key
     * @param pk The operator's public key itself
     * @param apkHashIndex The index of the latest (i.e. the new) APK update
     * @param apkHash The keccak256 hash of the new Aggregate Public Key
     */
    event Registration(
        address indexed operator,
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
        uint256[] memory _quorumBips,
        StrategyAndWeightingMultiplier[] memory _firstQuorumStrategiesConsideredAndMultipliers,
        StrategyAndWeightingMultiplier[] memory _secondQuorumStrategiesConsideredAndMultipliers
    )
        RegistryBase(
            _repository,
            _delegation,
            _investmentManager,
            _NUMBER_OF_QUORUMS,
            _quorumBips,
            _firstQuorumStrategiesConsideredAndMultipliers,
            _secondQuorumStrategiesConsideredAndMultipliers
        )
    {
        /** 
         * @dev Initialized value is the generator of G2 group. It is necessary in order to do 
         *      addition in Jacobian coordinate system.
         */
        uint256[4] memory initApk = [BLS.G2x0, BLS.G2x1, BLS.G2y0, BLS.G2y1];
        _processApkUpdate(initApk);
    }

    /**
     * @notice called for registering as a operator
     * @param operatorType specifies whether the operator want to register as staker for one or both quorums
     * @param data is the calldata that contains the coordinates for pubkey on G2 and signature on G1
     * @param socket is the socket address of the operator
     */ 
    function registerOperator(
        uint8 operatorType,
        bytes calldata data,
        string calldata socket
    ) external virtual {        
        _registerOperator(msg.sender, operatorType, data, socket);
    }
    
    /**
     * @param operator is the node who is registering to be a operator
     * @param operatorType specifies whether the operator want to register as staker for one or both quorums
     * @param data is the calldata that contains the coordinates for pubkey on G2 and signature on G1
     * @param socket is the socket address of the operator
     */
    function _registerOperator(
        address operator,
        uint8 operatorType,
        bytes calldata data,
        string calldata socket
    ) internal {

        OperatorStake memory _operatorStake = _registrationStakeEvaluation(operator, operatorType);

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
        
        // our addition algorithm doesn't work in this case, since it won't properly handle `x + x`, per @gpsanant
        require(pubkeyHash != apkHashes[apkHashes.length - 1], "BLSRegistry._registerOperator: Apk and pubkey cannot be the same");

        // record the APK update and get the hash of the new APK
        bytes32 newApkHash = _processApkUpdate(newApk);

        // add the operator to the list of registrants and do accounting
        _addRegistrant(operator, pubkeyHash, _operatorStake, socket);
            
        emit Registration(operator, pubkeyHash, pk, uint32(apkHashes.length - 1), newApkHash);
    }

    /**
     * @notice Used by an operator to de-register itself from providing service to the middleware.
     * @param pubkeyToRemoveAff is the sender's pubkey in affine coordinates
     * @param index is the sender's location in the dynamic array `operatorList`
     */
    function deregisterOperator(uint256[4] memory pubkeyToRemoveAff, uint32 index) external virtual returns (bool) {
        _deregisterOperator(pubkeyToRemoveAff, index);
        return true;
    }

    function _deregisterOperator(uint256[4] memory pubkeyToRemoveAff, uint32 index) internal {
        // verify that the `msg.sender` is an active operator and that they've provided the correct `index`
        _deregistrationCheck(msg.sender, index);
        
        /**
         * @notice verify that the sender is a operator that is doing deregistration for itself
         * @dev Fetch operator's stored pubkeyHash
         */
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
        _removeRegistrant(pubkeyHash, index);

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
     * @notice Used for updating information on deposits of nodes.
     * @param operators are the nodes whose deposit information is getting updated
     */
    function updateStakes(address[] calldata operators) external {
        // copy total stake to memory
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];

        // placeholders reused inside of loop
        OperatorStake memory currentStakes;
        bytes32 pubkeyHash;
        uint256 operatorsLength = operators.length;
        // iterating over all the tuples that are to be updated
        for (uint256 i = 0; i < operatorsLength; ) {
            // get operator's pubkeyHash
            pubkeyHash = registry[operators[i]].pubkeyHash;
            // fetch operator's existing stakes
            currentStakes = pubkeyHashToStakeHistory[pubkeyHash][pubkeyHashToStakeHistory[pubkeyHash].length - 1];
            // decrease _totalStake by operator's existing stakes
            _totalStake.firstQuorumStake -= currentStakes.firstQuorumStake;
            _totalStake.secondQuorumStake -= currentStakes.secondQuorumStake;

            // update the stake for the i-th operator
            currentStakes = _updateOperatorStake(operators[i], pubkeyHash, currentStakes);

            // increase _totalStake by operator's updated stakes
            _totalStake.firstQuorumStake += currentStakes.firstQuorumStake;
            _totalStake.secondQuorumStake += currentStakes.secondQuorumStake;

            unchecked {
                ++i;
            }
        }

        // update storage of total stake
        _recordTotalStakeUpdate(_totalStake);
    }

    /**
     * @notice Updates the stored APK to `newApk`, calculates its hash, and pushes new entries to the `apkUpdates` and `apkHashes` arrays
     * @param newApk The updated APK. This will be the `apk` after this function runs!
     */
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
        external
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

    function getApkUpdatesLength() external view returns (uint256) {
        return apkUpdates.length;
    }

    function getApkHashesLength() external view returns (uint256) {
        return apkHashes.length;
    }
}


