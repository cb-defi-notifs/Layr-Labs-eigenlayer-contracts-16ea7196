// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IServiceManager.sol";
import "../interfaces/IRegistry.sol";
import "../libraries/BytesLib.sol";
import "./Repository.sol";
import "./VoteWeigherBase.sol";
import "../libraries/BLS.sol";

import "ds-test/test.sol";

/**
 * @notice This contract is used for 
            - registering new operators 
            - committing to and finalizing de-registration as an operator 
            - updating the stakes of the operator
 */

contract BLSRegistry is
    IRegistry,
    VoteWeigherBase,
    DSTest
{
    using BytesLib for bytes;

    // DATA STRUCTURES 
    /**
     * @notice  Data structure for storing info on operators to be used for:
     *           - sending data by the sequencer
     *           - payment and associated challenges
     */
    struct Registrant {
        // hash of pubkey of the operator
        bytes32 pubkeyHash;

        // id is always unique
        uint32 id;

        // corresponds to position in registrantList
        uint64 index;

        // start block from which the  operator has been registered
        uint32 fromTaskNumber;

        // UTC time until which this operator is supposed to serve its obligations to this middleware
        // set only when committing to deregistration
        uint32 serveUntil;

        // indicates whether the operator is actively registered for storing data or not 
        uint8 active; //bool

        // socket address of the node
        string socket;

        uint256 deregisterTime;
    }

    // struct used to give definitive ordering to operators at each task number
    struct OperatorIndex {
        // task number at which operator index changed
        // note that the operator's index is different *for this task number*, i.e. the new index is inclusive of this value
        uint32 toTaskNumber;
        // index of the operator in array of operators, or the total number of operators if in the 'totalOperatorsHistory'
        uint32 index;
    }


    // CONSTANTS
    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant REGISTRATION_TYPEHASH =
        keccak256(
            "Registration(address operator,address registrationContract,uint256 expiry)"
        );

    uint8 internal constant _NUMBER_OF_QUORUMS = 2;

    // number of registrants of this service
    uint64 public numRegistrants;  

    uint128 public nodeEthStake = 1 wei;
    uint128 public nodeEigenStake = 1 wei;
    
    /// @notice EIP-712 Domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @notice a sequential counter that is incremented whenver new operator registers
    uint32 public nextRegistrantId;

    /// @notice used for storing Registrant info on each operator while registration
    mapping(address => Registrant) public registry;

    /// @notice used for storing the list of current and past registered operators 
    address[] public registrantList;

    /// @notice array of the history of the total stakes
    OperatorStake[] public totalStakeHistory;

    /// @notice array of the history of the number of operators, and the taskNumbers at which the number of operators changed
    OperatorIndex[] public totalOperatorsHistory;

    /// @notice mapping from operator's pubkeyhash to the history of their stake updates
    mapping(bytes32 => OperatorStake[]) public pubkeyHashToStakeHistory;

    /// @notice mapping from operator's pubkeyhash to the history of their index in the array of all operators
    mapping(bytes32 => OperatorIndex[]) public pubkeyHashToIndexHistory;

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
    uint256[4] public apk = [G2x0, G2x1, G2y0, G2y1];


    // EVENTS
    event StakeAdded(
        address operator,
        uint96 ethStake,
        uint96 eigenStake,
        uint256 updateNumber,
        uint32 updateBlockNumber,
        uint32 prevUpdateBlockNumber
    );
    // uint48 prevUpdatetaskNumber

    event StakeUpdate(
        address operator,
        uint96 ethStake,
        uint96 eigenStake,
        uint32 updateBlockNumber,
        uint32 prevUpdateBlockNumber
    );

    /**
     * @notice
     */
    event Registration(
        address indexed registrant,
        uint256[4] pk,
        uint32 apkHashIndex,
        bytes32 apkHash
    );

    event Deregistration(
        address registrant
    );

    constructor(
        Repository _repository,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager,
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
            abi.encode(DOMAIN_TYPEHASH, bytes("EigenLayr"), block.chainid)
        );
        // push an empty OperatorStake struct to the total stake history
        OperatorStake memory _totalStake;
        totalStakeHistory.push(_totalStake);

        // push an empty OperatorIndex struct to the total operators history
        OperatorIndex memory _totalOperators;
        totalOperatorsHistory.push(_totalOperators);

        uint256 length = _ethStrategiesConsideredAndMultipliers.length;
        for (uint256 i = 0; i < length; ++i) {
            strategiesConsideredAndMultipliers[0].push(_ethStrategiesConsideredAndMultipliers[i]);            
        }
        length = _eigenStrategiesConsideredAndMultipliers.length;
        for (uint256 i = 0; i < length; ++i) {
            strategiesConsideredAndMultipliers[1].push(_eigenStrategiesConsideredAndMultipliers[i]);            
        }
    }

    /**
     * @notice returns the total Eigen delegated by delegators with this operator
     */
    /**
     * @dev minimum delegation limit of nodeEigenStake has to be satisfied.
     */
    function weightOfOperatorEigen(address operator)
        public
        override
        returns (uint96)
    {
        uint96 eigenAmount = super.weightOfOperatorEigen(operator);

        // check that minimum delegation limit is satisfied
        return eigenAmount < nodeEigenStake ? 0 : eigenAmount;
    }

    /**
        @notice returns the total ETH delegated by delegators with this operator.
                Accounts for both ETH used for staking in settlement layer (via operator)
                and the ETH-denominated value of the shares in the investment strategies.
                Note that the middleware can decide for itself how much weight it wants to
                give to the ETH that is being used for staking in settlement layer.
     */
    /**
     * @dev minimum delegation limit of nodeEthStake has to be satisfied.
     */
    function weightOfOperatorEth(address operator)
        public
        override
        returns (uint96)
    {
        uint96 amount = super.weightOfOperatorEth(operator);

        // check that minimum delegation limit is satisfied
        return amount < nodeEthStake ? 0 : amount;
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

        // get current DataStoreId from ServiceManager
        uint32 currentTaskNumber = serviceManager.taskNumber();   
        
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
        popRegistrant(pubkeyHash,index,currentTaskNumber);


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

        //decrement number of registrants
        unchecked {
            --numRegistrants;
        }


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

        // update aggregated pubkey coordinates
        apkUpdates.push(currentTaskNumber);

        // store hash of updated aggregated pubkey
        apkHashes.push(keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3])));

        emit Deregistration(msg.sender);
    }



    function popRegistrant(bytes32 pubkeyHash, uint32 index, uint32 currentTaskNumber) internal {
        // Removes the registrant with the given pubkeyHash from the index in registrantList

        // Update index info for old operator
        // store taskNumber at which operator index changed (stopped being applicable)
        pubkeyHashToIndexHistory[pubkeyHash][pubkeyHashToIndexHistory[pubkeyHash].length - 1].toTaskNumber = currentTaskNumber;

        // Update index info for operator at end of list, if they are not the same as the removed operator
        if (index < registrantList.length - 1){
            // get existing operator at end of list, and retrieve their pubkeyHash
            address addr = registrantList[registrantList.length - 1];
            Registrant memory registrant = registry[addr];
            pubkeyHash = registrant.pubkeyHash;

            // store taskNumber at which operator index changed
            pubkeyHashToIndexHistory[pubkeyHash][pubkeyHashToIndexHistory[pubkeyHash].length - 1].toTaskNumber = currentTaskNumber;
            // push new 'OperatorIndex' struct to operator's array of historical indices, with 'index' set equal to 'index' input
            OperatorIndex memory operatorIndex;
            operatorIndex.index = index;
            pubkeyHashToIndexHistory[pubkeyHash].push(operatorIndex);

            registrantList[index] = addr;
        }

        registrantList.pop();

        // Update totalOperatorsHistory
        // set the 'to' field on the last entry *so far* in 'totalOperatorsHistory'
        totalOperatorsHistory[totalOperatorsHistory.length - 1].toTaskNumber = currentTaskNumber;
        // push a new entry to 'totalOperatorsHistory', with 'index' field set equal to the new amount of operators
        OperatorIndex memory _totalOperators;
        _totalOperators.index = uint32(registrantList.length);
        totalOperatorsHistory.push(_totalOperators);
    }

    
    function getOperatorIndex(address operator, uint32 taskNumber, uint32 index) public view returns (uint32) {

        Registrant memory registrant = registry[operator];
        bytes32 pubkeyHash = registrant.pubkeyHash;

        require(index < uint32(pubkeyHashToIndexHistory[pubkeyHash].length), "Operator indexHistory index exceeds array length");
        // since the 'to' field represents the taskNumber at which a new index started
        // it is OK if the previous array entry has 'to' == taskNumber, so we check not strict inequality here
        require(
            index == 0 || pubkeyHashToIndexHistory[pubkeyHash][index - 1].toTaskNumber <= taskNumber,
            "Operator indexHistory index is too high"
        );
        OperatorIndex memory operatorIndex = pubkeyHashToIndexHistory[pubkeyHash][index];
        // when deregistering, the operator does *not* serve the currentTaskNumber -- 'to' gets set (from zero) to the currentTaskNumber on deregistration
        // since the 'to' field represents the taskNumber at which a new index started, we want to check strict inequality here
        require(operatorIndex.toTaskNumber == 0 || taskNumber < operatorIndex.toTaskNumber, "indexHistory index is too low");
        return operatorIndex.index;
    }

    function getTotalOperators(uint32 taskNumber, uint32 index) public view returns (uint32) {

        require(index < uint32(totalOperatorsHistory.length), "TotalOperator indexHistory index exceeds array length");
        // since the 'to' field represents the taskNumber at which a new index started
        // it is OK if the previous array entry has 'to' == taskNumber, so we check not strict inequality here
        require(
            index == 0 || totalOperatorsHistory[index - 1].toTaskNumber <= taskNumber,
            "TotalOperator indexHistory index is too high"
        );
        OperatorIndex memory operatorIndex = totalOperatorsHistory[index];
        // since the 'to' field represents the taskNumber at which a new index started, we want to check strict inequality here
        require(operatorIndex.toTaskNumber == 0 || taskNumber < operatorIndex.toTaskNumber, "indexHistory index is too low");
        return operatorIndex.index;
        
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
        pubkeyToRemoveJac[2] = (MODULUS - pubkeyToRemoveJac[2]) % MODULUS;
        pubkeyToRemoveJac[3] = (MODULUS - pubkeyToRemoveJac[3]) % MODULUS;
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
            newStakes.ethStake = weightOfOperatorEth(operators[i]);
            newStakes.eigenStake = weightOfOperatorEigen(operators[i]);

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
     @notice returns task number from when operator has been registered.
     */
    function getOperatorFromTaskNumber(address operator)
        public
        view
        returns (uint32)
    {
        return registry[operator].fromTaskNumber;
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
    function getOperatorId(address operator) public view returns (uint32) {
        return registry[operator].id;
    }


    /// @notice returns the active status for the specified operator
    function getOperatorType(address operator) public view returns (uint8) {
        return registry[operator].active;
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


    function getOperatorPubkeyHash(address operator) public view returns(bytes32) {
        return registry[operator].pubkeyHash;
    }

    function getStakeFromPubkeyHashAndIndex(bytes32 pubkeyHash, uint256 index)
        public
        view
        returns (OperatorStake memory)
    {
        
        return pubkeyHashToStakeHistory[pubkeyHash][index];
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
    ) internal virtual {
        require(
            registry[operator].active == 0,
            "Operator is already registered"
        );

        OperatorStake memory _operatorStake;
        
        // if first bit of registrantType is '1', then operator wants to be an ETH validator
        if ((registrantType & 1) == 1) {
            // if operator want to be an "ETH" validator, check that they meet the
            // minimum requirements on how much ETH it must deposit
            _operatorStake.ethStake = uint96(weightOfOperatorEth(operator));
            require(
                _operatorStake.ethStake >= nodeEthStake,
                "Not enough eth value staked"
            );
        }

        //if second bit of registrantType is '1', then operator wants to be an EIGEN validator
        if ((registrantType & 2) == 2) {
            // if operator want to be an "Eigen" validator, check that they meet the
            // minimum requirements on how much Eigen it must deposit
            _operatorStake.eigenStake = uint96(weightOfOperatorEigen(operator));
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
            (pk[0], pk[1], pk[2], pk[3]) = BLS.verifyBLSSigOfPubKeyHash(data, 164);
            
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

        
        // emit log_bytes(getCompressedApk());
        // emit log_named_uint("x", input[0]);
        // emit log_named_uint("y", getYParity(input[0], input[1]) ? 0 : 1);



        
        /**
         @notice some book-keeping for aggregated pubkey
         */
        // get current task number from ServiceManager
        uint32 currentTaskNumber = IServiceManager(address(repository.serviceManager())).taskNumber();

        // store the current tasknumber in which the aggregated pubkey is being updated 
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
            index: numRegistrants,
            active: registrantType,
            fromTaskNumber: currentTaskNumber,
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
        {
            // set the 'to' field on the last entry *so far* in 'totalOperatorsHistory'
            totalOperatorsHistory[totalOperatorsHistory.length - 1].toTaskNumber = currentTaskNumber;
            // push a new entry to 'totalOperatorsHistory', with 'index' field set equal to the new amount of operators
            OperatorIndex memory _totalOperators;
            _totalOperators.index = uint32(registrantList.length);
            totalOperatorsHistory.push(_totalOperators);
        }

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

        // increment number of registrants
        unchecked {
            ++numRegistrants;
        }
            
        emit Registration(operator, pk, uint32(apkHashes.length)-1, newApkHash);
    }

    function getMostRecentStakeByOperator(address operator) public view returns (OperatorStake memory) {
        bytes32 pubkeyHash = registry[operator].pubkeyHash;
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

    function getApkHashesLength() external view returns (uint256) {
        return apkHashes.length;
    }

    function getOperatorStatus(address operator) external view returns(uint8) {
        return registry[operator].active;
    }

    /**
     @notice returns task number from when operator has been registered.
     */
    function getFromTaskNumberForOperator(address operator)
        public
        view
        returns (uint32)
    {
        return registry[operator].fromTaskNumber;
    }

    function getOperatorDeregisterTime(address operator)
        public
        view
        returns (uint256)
    {
        return registry[operator].deregisterTime;
    }
}


