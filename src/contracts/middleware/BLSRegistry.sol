// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "./RegistryBase.sol";

import "forge-std/Test.sol";

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
    uint256[4] public apk = [BLS.G2x0, BLS.G2x1, BLS.G2y0, BLS.G2y1];

    
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
    {}

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
        require(
            registry[operator].active == 0,
            "Operator is already registered"
        );

        OperatorStake memory _operatorStake;

        // if first bit of registrantType is '1', then operator wants to be an ETH validator
        if ((registrantType & 1) == 1) {
            // if operator want to be an "ETH" validator, check that they meet the
            // minimum requirements on how much ETH it must deposit
            _operatorStake.ethStake = uint96(weightOfOperator(operator, 0));
            require(
                _operatorStake.ethStake >= nodeEthStake,
                "Not enough eth value staked"
            );
        }

        //if second bit of registrantType is '1', then operator wants to be an EIGEN validator
        if ((registrantType & 2) == 2) {
            // if operator want to be an "Eigen" validator, check that they meet the
            // minimum requirements on how much Eigen it must deposit
            _operatorStake.eigenStake = uint96(weightOfOperator(operator, 1));
            require(
                _operatorStake.eigenStake >= nodeEigenStake,
                "Not enough eigen staked"
            );
        }

        require(
            _operatorStake.ethStake > 0 || _operatorStake.eigenStake > 0,
            "must register as at least one type of validator"
        );
        
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

            apk = newApk;
        }
        
        // getting pubkey hash 
        bytes32 pubkeyHash = keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3]));   

        if (apkUpdates.length != 0) {
            // addition doesn't work in this case 
            // our addition algorithm doesn't work
            require(pubkeyHash != apkHashes[apkHashes.length - 1], "Apk and pubkey cannot be the same");
        }
        
        /**
         @notice some book-keeping for aggregated pubkey
         */
        // get current task number from ServiceManager
        uint32 currentTaskNumber = IServiceManager(address(repository.serviceManager())).taskNumber();

        // store the current block number in which the aggregated pubkey is being updated 
        apkUpdates.push(uint32(block.number));
        
        //store the hash of aggregate pubkey
        bytes32 newApkHash = keccak256(abi.encodePacked(newApk[0], newApk[1], newApk[2], newApk[3]));
        apkHashes.push(newApkHash);    

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
            active: registrantType,
            fromTaskNumber: currentTaskNumber,
            fromBlockNumber: uint32(block.number),
            serveUntil: 0,
            // extract the socket address
            socket: socket,
            deregisterTime: 0
        });

        // record the operator being registered
        registrantList.push(operator);

        // record operator's index in list of operators
        OperatorIndex memory operatorIndex;
        operatorIndex.index = uint32(registrantList.length - 1);
        pubkeyHashToIndexHistory[pubkeyHash].push(operatorIndex);
        
        // Update totalOperatorsHistory
        _updateTotalOperatorsHistory();

        // update the counter for registrant ID
        unchecked {
            ++nextRegistrantId;
        }
        
        
        {
            /**
            @notice some book-keeping for recoding updated total stake
            */
            OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];
            /**
            * update total Eigen and ETH that are being employed by the operator for securing
            * the queries from middleware via EigenLayr
            */

            _totalStake.ethStake += _operatorStake.ethStake;
            _totalStake.eigenStake += _operatorStake.eigenStake;
            _totalStake.updateBlockNumber = uint32(block.number);            
            // linking with the most recent stake recordd in the past
            totalStakeHistory[totalStakeHistory.length - 1].nextUpdateBlockNumber = uint32(block.number);
            totalStakeHistory.push(_totalStake);
        }
            
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
        require(
            registry[msg.sender].active > 0,
            "Operator is already registered"
        );

        require(
            msg.sender == registrantList[index],
            "Incorrect index supplied"
        );

        IServiceManager serviceManager = repository.serviceManager();

        // must store till the latest time a dump expires
        /**
         @notice this info is used in forced disclosure
         */
        registry[msg.sender].serveUntil = serviceManager.latestTime();


        // committing to not signing off on any more data that is being asserted into DataLayr
        registry[msg.sender].active = 0;

        registry[msg.sender].deregisterTime = block.timestamp;
        
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
        require(pubkeyHash == pubkeyHashFromInput, "incorrect input for commitDeregistration");

        // determine current stakes
        OperatorStake memory currentStakes = pubkeyHashToStakeHistory[
            pubkeyHash
        ][pubkeyHashToStakeHistory[pubkeyHash].length - 1];

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

        //set next task number in prev stakes
        pubkeyHashToStakeHistory[pubkeyHash][
            pubkeyHashToStakeHistory[pubkeyHash].length - 1
        ].nextUpdateBlockNumber = uint32(block.number);

        // push new stake to storage
        pubkeyHashToStakeHistory[pubkeyHash].push(newStakes);

        // Update registrant list and update index histories
        address swappedOperator = _popRegistrant(pubkeyHash,index);

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

        /**
         @notice update the aggregated public key of all registered operators and record
                 this update in history
         */
        // get existing aggregate public key
        uint256[4] memory pk = apk;
        // remove signer's pubkey from aggregate public key
        (pk[0], pk[1], pk[2], pk[3]) = removePubkeyFromAggregate(pubkeyToRemoveAff, pk);
        // update stored aggregate public key
        apk = pk;

        // store the current block number in which the aggregated pubkey is being updated 
        apkUpdates.push(uint32(block.number));

        // store hash of updated aggregated pubkey
        apkHashes.push(keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3])));

        emit Deregistration(msg.sender, swappedOperator);
    }

    /**
     @notice This function is for removing a pubkey from aggregated pubkey. The thesis of this operation:
              - conversion to Jacobian coordinates,
              - do the subtraction of pubkey from aggregated pubkey,
              - convert the updated aggregated pubkey back to affine coordinates.   
     */
    /**
     @param pubkeyToRemoveAff is the pubkey that is to be removed,
     @param existingAggPubkeyAff is the aggregated pubkey.
     */
    /**
     @dev Jacobian coordinates are stored in the form [x0, x1, y0, y1, z0, z1]
     */ 
    function removePubkeyFromAggregate(uint256[4] memory pubkeyToRemoveAff, uint256[4] memory existingAggPubkeyAff) internal view returns (uint256, uint256, uint256, uint256) {
        uint256[6] memory pubkeyToRemoveJac;
        uint256[6] memory existingAggPubkeyJac;

        // get x0, x1, y0, y1 from affine coordinates
        for (uint256 i = 0; i < 4;) {
            pubkeyToRemoveJac[i] = pubkeyToRemoveAff[i];
            existingAggPubkeyJac[i] = existingAggPubkeyAff[i];
            unchecked {
                ++i;
            }
        }
        // set z0 = 1
        pubkeyToRemoveJac[4] = 1;
        existingAggPubkeyJac[4] = 1;


        /**
         @notice subtract pubkeyToRemoveJac from the aggregate pubkey
         */
        // negate pubkeyToRemoveJac  
        pubkeyToRemoveJac[2] = (BLS.MODULUS - pubkeyToRemoveJac[2]) % BLS.MODULUS;
        pubkeyToRemoveJac[3] = (BLS.MODULUS - pubkeyToRemoveJac[3]) % BLS.MODULUS;
        // add the negation to existingAggPubkeyJac
        BLS.addJac(existingAggPubkeyJac, pubkeyToRemoveJac);

        // 'addJac' function above modifies the first input in memory, so now we can just return it (but first transform it back to affine)
        return (BLS.jacToAff(existingAggPubkeyJac));
    }

    /**
     * @notice Used for updating information on ETH and EIGEN deposits of nodes.
     */
    /**
     * @param operators are the nodes whose information on their ETH and EIGEN deposits
     *        getting updated
     */
    function updateStakes(address[] calldata operators) public {
        // copy total stake to memory
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];

        // TODO: test if declaring more variables outside of loop decreases gas usage
        uint256 operatorsLength = operators.length;
        // iterating over all the tuples that are to be updated
        for (uint256 i = 0; i < operatorsLength; ) {
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
            //set next task number in prev stakes
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

        // update storage of total stake
        _totalStake.updateBlockNumber = uint32(block.number);
        totalStakeHistory[totalStakeHistory.length - 1].nextUpdateBlockNumber = uint32(block.number);
        totalStakeHistory.push(_totalStake);
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
            "Index too recent"
        );

        // if not last update
        if (index != apkUpdates.length - 1) {
            require(
                blockNumber < apkUpdates[index + 1],
                "Not latest valid apk update"
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


