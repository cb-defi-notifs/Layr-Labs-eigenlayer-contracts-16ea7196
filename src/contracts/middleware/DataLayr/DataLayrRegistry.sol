// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IDataLayrRegistry.sol";
import "../../libraries/BytesLib.sol";
import "../Repository.sol";
import "../VoteWeigherBase.sol";
import "../RegistrationManagerBaseMinusRepository.sol";
import "../../libraries/SignatureCompaction.sol";
import "../../libraries/BLS.sol";

import "ds-test/test.sol";

/**
 * @notice This contract is used for 
            - registering new DataLayr operators 
            - committing to and finalizing de-registration as an operator from DataLayr 
            - updating the stakes of the DataLayr operator
 */

contract DataLayrRegistry is
    IDataLayrRegistry,
    VoteWeigherBase,
    IRegistrationManager,
    DSTest
{
    using BytesLib for bytes;

    // CONSTANTS
    uint256 constant MODULUS =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant REGISTRATION_TYPEHASH =
        keccak256(
            "Registration(address operator,address registrationContract,uint256 expiry)"
        );


    // DATA STRUCTURES 
    /**
     * @notice  Data structure for storing info on DataLayr operators that would be used for:
     *           - sending data by the sequencer
     *           - querying by any challenger/retriever
     *           - payment and associated challenges
     */
    struct Registrant {
        // hash of pubkey of the DataLayr operator
        bytes32 pubkeyHash;

        // id is always unique
        uint32 id;

        // corresponds to position in registrantList
        uint64 index;

        // dump number from which the DataLayr operator has been registered
        uint32 fromDumpNumber;

        // time until which this DataLayr operator is supposed to serve its obligations in DataLayr 
        // set only when committing to deregistration
        uint32 to;

        // indicates whether the DataLayr operator is actively registered for storing data or not 
        uint8 active; //bool

        // socket address of the DataLayr node
        string socket;
    }

    // number of registrants of this service
    uint64 public numRegistrants;  

    uint128 public dlnEthStake = 1 wei;
    uint128 public dlnEigenStake = 1 wei;
    
    /// @notice EIP-712 Domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    /** 
      @notice the latest expiry period (in UTC timestamp) out of all the active Data blobs stored in DataLayr;
              updated at every call to initDataStore in DataLayrServiceManager.sol  

              This would be used for recording the time until which a DataLayr operator is obligated
              to serve while committing deregistration.
     */
    uint32 public latestTime;


    /// @notice a sequential counter that is incremented whenver new operator registers
    uint32 public nextRegistrantId;


    /// @notice used for storing Registrant info on each DataLayr operator while registration
    mapping(address => Registrant) public registry;

    /// @notice used for storing the list of current and past registered DataLayr operators 
    address[] public registrantList;

    // struct OperatorStake {
    //     uint32 dumpNumber;
    //     uint32 nextUpdateDumpNumber;
    //     uint96 ethStake;
    //     uint96 eigenStake;
    // }
    /// @notice array of the history of the total stakes
    OperatorStake[] public totalStakeHistory;

    /// @notice mapping from operator's pubkeyhash to the history of their stake updates
    mapping(bytes32 => OperatorStake[]) public pubkeyHashToStakeHistory;


    /// @notice the dump numbers in which the aggregated pubkeys are updated
    uint32[] public apkUpdates;


    /**
     @notice list of keccak256(apk_x0, apk_x1, apk_y0, apk_y1) of DataLayr operators, 
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
    uint256[4] public apk = [10857046999023057135944570762232829481370756359578518086990519993285655852781,11559732032986387107991004021392285783925812861821192530917403151452391805634,8495653923123431417604973247489272438418190587263600148770280649306958101930,4082367875863433681332203403145435568316851327593401208105741076214120093531];

    

    // EVENTS
    event StakeAdded(
        address operator,
        uint96 ethStake,
        uint96 eigenStake,
        uint256 updateNumber,
        uint32 dumpNumber,
        uint32 prevDumpNumber
    );
    // uint48 prevUpdateDumpNumber

    event StakeUpdate(
        address operator,
        uint96 ethStake,
        uint96 eigenStake,
        uint32 dumpNumber,
        uint32 prevUpdateDumpNumber
    );

    /**
     * @notice
     */
    event Registration(
        address registrant,
        uint256[4] pk,
        uint32 apkHashIndex,
        bytes32 apkHash
    );

    event Deregistration(
        address registrant
    );

    // MODIFIERS
    modifier onlyRepository() {
        require(address(repository) == msg.sender, "onlyRepository");
        _;
    }


    constructor(
        Repository _repository,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager,
        uint256 _consensusLayerEthToEth,
        IInvestmentStrategy[] memory _strategiesConsidered
    )
        VoteWeigherBase(
            _repository,
            _delegation,
            _investmentManager,
            _consensusLayerEthToEth,
            _strategiesConsidered
        )
    {
        //apk_0 = g2Gen
        // initialize the DOMAIN_SEPARATOR for signatures
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(DOMAIN_TYPEHASH, bytes("EigenLayr"), block.chainid)
        );
        // push an empty OperatorStake object to the total stake history
        OperatorStake memory _totalStake;
        totalStakeHistory.push(_totalStake);
    }

    /**
     * @notice returns the total Eigen delegated by delegators with this operator
     */
    /**
     * @dev minimum delegation limit of dlnEigenStake has to be satisfied.
     */
    function weightOfOperatorEigen(address operator)
        public
        view
        override
        returns (uint128)
    {
        uint128 eigenAmount = super.weightOfOperatorEigen(operator);

        // check that minimum delegation limit is satisfied
        return eigenAmount < dlnEigenStake ? 0 : eigenAmount;
    }

    /**
        @notice returns the total ETH delegated by delegators with this operator.
                Accounts for both ETH used for staking in settlement layer (via operator)
                and the ETH-denominated value of the shares in the investment strategies.
                Note that the DataLayr can decide for itself how much weight it wants to
                give to the ETH that is being used for staking in settlement layer.
     */
    /**
     * @dev minimum delegation limit of dlnEthStake has to be satisfied.
     */
    function weightOfOperatorEth(address operator)
        public
        override
        returns (uint128)
    {
        uint128 amount = super.weightOfOperatorEth(operator);

        // check that minimum delegation limit is satisfied
        return amount < dlnEthStake ? 0 : amount;
    }

    /**
      @notice Used by an operator to de-register itself from providing service to the middleware.
     */
    /** 
      @param pubkeyToRemoveAff is the sender's pubkey in affine coordinates
     */
    function deregisterOperator(uint256[4] memory pubkeyToRemoveAff) external returns (bool) {
        require(
            registry[msg.sender].active > 0,
            "Operator is already registered"
        );


        // must store till the latest time a dump expires
        /**
         @notice this info is used in forced disclosure
         */
        registry[msg.sender].to = latestTime;


        // committing to not signing off on any more data that is being asserted into DataLayr
        registry[msg.sender].active = 0;



        // TODO: this logic is mostly copied from 'updateStakes' function. perhaps de-duplicating it is possible
        // get current dump number from DataLayrServiceManager
        uint32 currentDumpNumber = IDataLayrServiceManager(address(repository.serviceManager())).dumpNumber();        
        

        /**
         @notice verify that the sender is a DataLayr operator that is doing deregistration for itself 
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
         @notice recording the information pertaining to change in stake for this DataLayr operator in the history
         */
        // determine new stakes
        OperatorStake memory newStakes;
        // recording the current dump number where the operator stake got updated 
        newStakes.dumpNumber = currentDumpNumber;

        // setting total staked ETH for the DataLayr operator to 0
        newStakes.ethStake = uint96(0);
        // setting total staked Eigen for the DataLayr operator to 0
        newStakes.eigenStake = uint96(0);


        //set next dump number in prev stakes
        pubkeyHashToStakeHistory[pubkeyHash][
            pubkeyHashToStakeHistory[pubkeyHash].length - 1
        ].nextUpdateDumpNumber = currentDumpNumber;


        // push new stake to storage
        pubkeyHashToStakeHistory[pubkeyHash].push(newStakes);


        /**
         @notice  update info on ETH and Eigen staked with DataLayr
         */
        // subtract the staked Eigen and ETH of the operator that is getting deregistered from total stake
        // copy total stake to memory
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];
        _totalStake.ethStake -= currentStakes.ethStake;
        _totalStake.eigenStake -= currentStakes.eigenStake;
        _totalStake.dumpNumber = currentDumpNumber;
        totalStakeHistory[totalStakeHistory.length - 1].nextUpdateDumpNumber = currentDumpNumber;
        totalStakeHistory.push(_totalStake);

        //decrement number of registrants
        unchecked {
            --numRegistrants;
        }


        /**
         @notice update the aggregated public key of all registered DataLayr operators and record
                 this update in history
         */
        // get existing aggregate public key
        uint256[4] memory pk = apk;
        // remove signer's pubkey from aggregate public key
        (pk[0], pk[1], pk[2], pk[3]) = removePubkeyFromAggregate(pubkeyToRemoveAff, pk);
        // update stored aggregate public key
        apk = pk;

        // update aggregated pubkey coordinates
        apkUpdates.push(currentDumpNumber);

        // store hash of updated aggregated pubkey
        apkHashes.push(keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3])));

        emit Deregistration(msg.sender);
        return true;
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
     * @notice Used for updating information on ETH and EIGEN deposits of DataLayr nodes.
     */
    /**
     * @param operators are the DataLayr nodes whose information on their ETH and EIGEN deposits
     *        getting updated
     */
    function updateStakes(address[] calldata operators) public {
        // get current dump number from DataLayrServiceManager
        uint32 currentDumpNumber = IDataLayrServiceManager(
            address(repository.serviceManager())
        ).dumpNumber();

        uint256 operatorsLength = operators.length;

        // copy total stake to memory
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];

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

            newStakes.dumpNumber = currentDumpNumber;
            newStakes.ethStake = uint96(weightOfOperatorEth(operators[i]));
            newStakes.eigenStake = uint96(weightOfOperatorEigen(operators[i]));

            // check if minimum requirements have been met
            if (newStakes.ethStake < dlnEthStake) {
                newStakes.ethStake = uint96(0);
            }
            if (newStakes.eigenStake < dlnEigenStake) {
                newStakes.eigenStake = uint96(0);
            }
            //set next dump number in prev stakes
            pubkeyHashToStakeHistory[pubkeyHash][
                pubkeyHashToStakeHistory[pubkeyHash].length - 1
            ].nextUpdateDumpNumber = currentDumpNumber;
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
                currentDumpNumber,
                currentStakes.dumpNumber
            );
            unchecked {
                ++i;
            }
        }

        // update storage of total stake
        _totalStake.dumpNumber = currentDumpNumber;
        totalStakeHistory[totalStakeHistory.length - 1].nextUpdateDumpNumber = currentDumpNumber;
        totalStakeHistory.push(_totalStake);
    }


    /**
     @notice returns dump number from when operator has been registered.
     */
    function getOperatorFromDumpNumber(address operator)
        public
        view
        returns (uint32)
    {
        return registry[operator].fromDumpNumber;
    }

    function setDlnEigenStake(uint128 _dlnEigenStake)
        public
        onlyRepositoryGovernance
    {
        dlnEigenStake = _dlnEigenStake;
    }

    function setDlnEthStake(uint128 _dlnEthStake)
        public
        onlyRepositoryGovernance
    {
        dlnEthStake = _dlnEthStake;
    }


    /**
     @notice sets the latest time until which any of the active DataLayr operators that haven't committed
             yet to deregistration are supposed to serve.
     */
    function setLatestTime(uint32 _latestTime) public {
        require(
            address(repository.serviceManager()) == msg.sender,
            "only service manager can call this"
        );
        if (_latestTime > latestTime) {
            latestTime = _latestTime;
        }
    }


    /// @notice returns the unique ID of the specified DataLayr operator 
    function getOperatorId(address operator) public view returns (uint32) {
        return registry[operator].id;
    }


    /// @notice returns the active status for the specified DataLayr operator
    function getOperatorType(address operator) public view returns (uint8) {
        return registry[operator].active;
    }


    /**
     @notice get hash of a historical aggregated public key corresponding to a given index;
             called by checkSignatures in DataLayrSignatureChecker.sol.
     */
    function getCorrectApkHash(uint256 index, uint32 dumpNumberToConfirm)
        public
        view
        returns (bytes32)
    {
        require(
            dumpNumberToConfirm >= apkUpdates[index],
            "Index too recent"
        );

        // if not last update
        if (index != apkUpdates.length - 1) {
            require(
                dumpNumberToConfirm < apkUpdates[index + 1],
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
     @notice called for registering as a DataLayr operator
     */
    /**
     @param registrantType specifies whether the DataLayr operator want to register as ETH staker or Eigen stake or both
     @param data is the calldata that contains the coordinates for pubkey on G2 and signature on G1
     @param socket is the socket address of the DataLayr operator
     */ 
    function registerOperator(
        uint8 registrantType,
        bytes calldata data,
        string calldata socket
    ) public {
        _registerOperator(msg.sender, registrantType, data, socket);
    }


    /**
     @param operator is the node who is registering to be a DataLayr operator
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

        // TODO: shared struct type for this + registrantType, also used in Repository?
        OperatorStake memory _operatorStake;



        // if first bit of registrantType is '1', then operator wants to be an ETH validator
        if ((registrantType & 1) == 1) {
            // if operator want to be an "ETH" validator, check that they meet the
            // minimum requirements on how much ETH it must deposit
            _operatorStake.ethStake = uint96(weightOfOperatorEth(operator));
            require(
                _operatorStake.ethStake >= dlnEthStake,
                "Not enough eth value staked"
            );
        }

        //if second bit of registrantType is '1', then operator wants to be an EIGEN validator
        if ((registrantType & 2) == 2) {
            // if operator want to be an "Eigen" validator, check that they meet the
            // minimum requirements on how much Eigen it must deposit
            _operatorStake.eigenStake = uint96(weightOfOperatorEigen(operator));
            require(
                _operatorStake.eigenStake >= dlnEigenStake,
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
            (pk[0], pk[1], pk[2], pk[3]) = BLS.verifyBLSSigOfPubKeyHash(data, 132);

            // add pubkey to aggregated pukkey in Jacobian coordinates
            uint256[6] memory newApkJac = BLS.addJac([pk[0], pk[1], pk[2], pk[3], 1, 0], [apk[0], apk[1], apk[2], apk[3], 1, 0]);
            
            // convert back to Affine coordinates
            (newApk[0], newApk[1], newApk[2], newApk[3]) = BLS.jacToAff(newApkJac);

            apk = newApk;
        }

        // getting pubkey hash 
        bytes32 pubkeyHash = keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3]));


        // CRITIC: @Gautham please elaborate on the meaning of this snippet
        if (apkUpdates.length != 0) {
            // addition doesn't work in this case 
            require(pubkeyHash != apkHashes[apkHashes.length - 1], "Apk and pubkey cannot be the same");
        }

        // emit log_bytes(getCompressedApk());
        // emit log_named_uint("x", input[0]);
        // emit log_named_uint("y", getYParity(input[0], input[1]) ? 0 : 1);




        /**
         @notice some book-keeping for aggregated pubkey
         */
        // get current dump number from DataLayrServiceManager
        uint32 currentDumpNumber = IDataLayrServiceManager(address(repository.serviceManager())).dumpNumber();

        // store the current dumpnumber in which the aggregated pubkey is being updated 
        apkUpdates.push(currentDumpNumber);
        
        //store the hash of aggregate pubkey
        bytes32 newApkHash = keccak256(abi.encodePacked(newApk[0], newApk[1], newApk[2], newApk[3]));
        apkHashes.push(newApkHash);




        /**
         @notice some book-keeping for recording info pertaining to the DataLayr operator
         */
        // record the new stake for the DataLayr operator in the storage
        _operatorStake.dumpNumber = currentDumpNumber;
        pubkeyHashToStakeHistory[pubkeyHash].push(_operatorStake);
        
        // store the registrant's info in relation to DataLayr
        registry[operator] = Registrant({
            pubkeyHash: pubkeyHash,
            id: nextRegistrantId,
            index: numRegistrants,
            active: registrantType,
            // CRITIC: load from memory and save it in memory the first time above this other contract was called
            fromDumpNumber: IDataLayrServiceManager(address(repository.serviceManager())).dumpNumber(),
            to: 0,
            // extract the socket address
            socket: socket
        });

        // record the operator being registered
        registrantList.push(operator);

        // update the counter for registrant ID
        unchecked {
            ++nextRegistrantId;
        }
        
        
        
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
        _totalStake.dumpNumber = currentDumpNumber;
        // linking with the most recent stake recordd in the past
        totalStakeHistory[totalStakeHistory.length - 1].nextUpdateDumpNumber = currentDumpNumber;
        totalStakeHistory.push(_totalStake);



        //TODO: do we need this variable at all?
        // increment number of registrants
        unchecked {
            ++numRegistrants;
        }

        emit Registration(operator, pk, uint32(apkHashes.length), newApkHash);
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

    function getLengthOfTotalStakeHistory() external view returns (uint256) {
        return totalStakeHistory.length;
    }

    function getTotalStakeFromIndex(uint256 index) external view returns (OperatorStake memory) {
        return totalStakeHistory[index];
    }
}
